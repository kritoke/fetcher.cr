require "log"
require "uri"
require "socket"
require "./bounded_registry"
require "./validated_ip_store"
require "./lazy_store"

module Fetcher
  module URLValidator
    ALLOWED_SCHEMES = {"http", "https"}
    MAX_URL_LENGTH  = 2048

    # IPv4 CIDR ranges blocked for SSRF protection.
    # Format: {prefix_as_uint32, prefix_length, description}
    BLOCKED_IPV4_RANGES = [
      {0x0A000000_u32, 8, "10.0.0.0/8 (RFC 1918 private)"},
      {0xAC100000_u32, 12, "172.16.0.0/12 (RFC 1918 private)"},
      {0xC0A80000_u32, 16, "192.168.0.0/16 (RFC 1918 private)"},
      {0xA9FE0000_u32, 16, "169.254.0.0/16 (link-local)"},
      {0x64400000_u32, 10, "100.64.0.0/10 (CGNAT, RFC 6598)"},
      {0xC6120000_u32, 15, "198.18.0.0/15 (benchmark, RFC 2544)"},
      {0xE0000000_u32, 4, "224.0.0.0/4 (multicast)"},
      {0xF0000000_u32, 4, "240.0.0.0/4 (reserved)"},
      {0x00000000_u32, 8, "0.0.0.0/8 (current network)"},
      {0xC0000200_u32, 24, "192.0.2.0/24 (TEST-NET-1, RFC 5737)"},
      {0xC6336400_u32, 24, "198.51.100.0/24 (TEST-NET-2, RFC 5737)"},
      {0xCB007100_u32, 24, "203.0.113.0/24 (TEST-NET-3, RFC 5737)"},
    ]

    # DNS rebinding mitigation: track recently validated hostnames and their IPs
    DNS_RESOLVE_PORT = 80
    record ValidatedEntry,
      ip : Socket::IPAddress,
      timestamp : Time

    # Backwards-compatible store. We encapsulate the mutable cache in
    # ValidatedIpStore but keep a class-level default instance so existing
    # call-sites remain functional without signature changes.
    lazy_store(ValidatedIpStore, var_name: "validated_store", method_name: "validated_store")

    def self.clear_validated : Nil
      validated_store.clear
    end

    def self.register_ip(host : String, ip : Socket::IPAddress) : Nil
      validated_store.register(host, ip)
    end

    def self.purge_expired(expiry : Time::Span? = nil) : Nil
      validated_store.purge_expired(expiry)
    end

    def self.check_rebinding(host : String, current_ip : Socket::IPAddress) : Bool
      res = validated_store.check_rebinding(host, current_ip)
      return res unless res.nil?
      !blocked_ip?(current_ip)
    end

    def self.valid?(url : String?) : Bool
      return false if url.nil? || url.empty?
      return false if url.size > MAX_URL_LENGTH

      begin
        uri = URI.parse(url)
        normalized = normalize_uri(uri)
        validate_uri(normalized)
      rescue URI::Error
        false
      end
    end

    def self.safe_url(url : String?) : String
      return "#" unless valid?(url)
      url
    end

    # Service wrapper for dependency injection.
    # By default it delegates to the URLValidator module methods. Tests can
    # pass a custom object that implements the same instance methods to
    # CrestHttpClient for deterministic/mocked behavior.
    class Service
      def initialize
      end

      def valid?(url : String?) : Bool
        URLValidator.valid?(url)
      end

      def resolve_and_validate(url : String) : Bool
        URLValidator.resolve_and_validate(url)
      end

      def validate_connected_ip(host : String, connected_ip : Socket::IPAddress) : Bool
        URLValidator.validate_connected_ip(host, connected_ip)
      end

      def extract_domain(url : String) : String
        URLValidator.extract_domain(url)
      end

      def looks_like_ip?(host : String) : Bool
        URLValidator.looks_like_ip?(host)
      end

      def validate_ip(host : String) : Bool
        URLValidator.validate_ip(host)
      end

      def register_ip(host : String, ip : Socket::IPAddress) : Nil
        URLValidator.register_ip(host, ip)
      end
    end

    def self.default_service : Service
      Service.new
    end

    SAFE_SCHEMES      = {"http", "https"}
    DANGEROUS_SCHEMES = {"javascript", "vbscript", "data", "file", "ftp", "jar", "mailto"}

    # Permissive scheme check: returns true for nil/empty, relative URLs
    # (no colon), and http/https URLs. Returns false only for explicitly
    # dangerous schemes (javascript:, data:, vbscript:, file:, etc.).
    #
    # This is intentionally more permissive than `valid?`, which requires
    # a full http/https URL with a valid host. `safe_scheme?` is used for
    # secondary URLs (comment URLs, author URLs, attachment URLs) that
    # may legitimately be relative paths like "/comments/123".
    #
    # Both methods block dangerous schemes -- `safe_scheme?` via the
    # DANGEROUS_SCHEMES blacklist, `valid?` via the ALLOWED_SCHEMES
    # whitelist. The defense-in-depth is: secondary URLs go through
    # safe_scheme? (permissive), primary URLs go through valid? (strict).
    def self.safe_scheme?(url : String?) : Bool
      return true if url.nil? || url.empty?

      colon_pos = url.index(":")
      return true unless colon_pos && colon_pos > 0

      scheme = url[0...colon_pos].downcase

      return false if DANGEROUS_SCHEMES.includes?(scheme)

      if url.includes?("://")
        SAFE_SCHEMES.includes?(scheme)
      else
        true
      end
    rescue ex
      Log.debug { "safe_scheme? failed for URL: #{ex.message}" }
      false
    end

    def self.resolve_and_validate(url : String) : Bool
      uri = URI.parse(url)
      normalized = normalize_uri(uri)
      return false unless validate_uri(normalized)

      host = uri.host
      return true if host.nil? || host.empty?
      return true unless looks_like_ip?(host)

      begin
        addr_info = Socket::Addrinfo.resolve(host, DNS_RESOLVE_PORT.to_s, type: Socket::Type::STREAM, protocol: Socket::Protocol::TCP)

        addr_info.each do |addr|
          next unless addr.family == Socket::Family::INET || addr.family == Socket::Family::INET6
          ip_address = addr.ip_address
          return false if blocked_ip?(ip_address)
          register_ip(host, ip_address)
        end
        true
      rescue Exception
        false
      end
    end

    def self.validate_connected_ip(host : String, connected_ip : Socket::IPAddress) : Bool
      check_rebinding(host, connected_ip)
    end

    def self.valid_redirect?(redirect_url : String) : Bool
      valid?(redirect_url) && resolve_and_validate(redirect_url)
    end

    # Extract host/domain from a URL string. Returns "default" on error.
    def self.extract_domain(url : String) : String
      uri = URI.parse(url)
      uri.host || "default"
    rescue ex
      Log.debug { "extract_domain failed for #{url}: #{ex.message}" }
      "default"
    end

    private def self.normalize_uri(uri : URI) : URI
      path = uri.path
      if path && (path.includes?("/..") || path.includes?("/."))
        resolved = path.split("/").reduce([] of String) do |acc, segment|
          case segment
          when ".."    then acc.pop?; acc
          when ".", "" then acc
          else              acc << segment
          end
        end
        uri = uri.dup
        uri.path = resolved.join("/")
        uri.path = "/#{uri.path}" unless uri.path.starts_with?("/")
      end
      uri
    end

    private def self.validate_uri(uri : URI) : Bool
      scheme = uri.scheme.try(&.downcase)
      return false unless scheme && ALLOWED_SCHEMES.includes?(scheme)

      host = uri.host
      return false if host.nil? || host.empty?

      clean_host = clean_ipv6(host)
      return false if block_localhost?(clean_host)

      !looks_like_ip?(clean_host) || validate_ip(clean_host)
    end

    IPV4_OR_HEX = /^[0-9a-fA-F.:]+$/

    def self.looks_like_ip?(host : String) : Bool
      return false if host.empty?

      # Bracketed IPv6 (e.g. [::1]) is clearly an IP
      return true if host.starts_with?("[") && host.ends_with?("]")

      # Try to parse using Socket::IPAddress for robust detection. This covers
      # IPv4, IPv6, and mapped IPv4 addresses. Fallback to simple heuristics
      # only if parsing fails.
      begin
        Socket::IPAddress.new(host, DNS_RESOLVE_PORT)
        true
      rescue ex
        # Fallback: if there's a colon it's likely IPv6-ish; if it starts with
        # a digit and matches hex/dot/colon chars, treat as IP-like.
        Log.debug { "looks_like_ip? parse failed for #{host}: #{ex.message}" }
        return true if host.includes?(":")
        return false unless host[0].ascii_number?
        host.matches?(IPV4_OR_HEX)
      end
    end

    private def self.clean_ipv6(host : String) : String
      if host.starts_with?("[") && host.ends_with?("]")
        host[1..-2]
      else
        host
      end
    end

    private def self.block_localhost?(host : String) : Bool
      host.downcase == "localhost" ||
        host.downcase.ends_with?(".localhost") ||
        host == "0.0.0.0" ||
        host == "::" # IPv6 unspecified address
    end

    private def self.validate_ip(host : String) : Bool
      ip_address = Socket::IPAddress.new(host, DNS_RESOLVE_PORT)
      !blocked_ip?(ip_address)
    rescue Socket::Error
      false
    end

    private def self.blocked_ip?(ip_address : Socket::IPAddress) : Bool
      ip_address.private? || ip_address.loopback? ||
        blocked_ipv6?(ip_address.address) ||
        ipv6_mapped_ipv4_blocked?(ip_address) ||
        blocked_ipv4?(ip_address)
    end

    # Check if an IPv6 address matches a blocked prefix.
    # Covers: fe80::/10 (link-local), fec0::/10 (site-local), fc00::/7 (unique local).
    private def self.blocked_ipv6?(address : String) : Bool
      return false unless address.includes?(":")
      downcase = address.downcase
      return true if downcase.starts_with?("fc") || downcase.starts_with?("fd") # fc00::/7 (unique local)
      return false unless downcase.starts_with?("fe")
      third = downcase[2]?
      return false unless third
      case third
      when '8', '9', 'a', 'b' then true # fe80::/10 (link-local)
      when 'c', 'd', 'e', 'f' then true # fec0::/10 (site-local)
      else                         false
      end
    rescue ex
      Log.debug { "blocked_ipv6? failed: #{ex.message}" }
      false
    end

    # Check if an IPv6-mapped IPv4 address (::ffff:x.x.x.x) contains a blocked IPv4.
    private def self.ipv6_mapped_ipv4_blocked?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      return false unless address.includes?(":") && address.downcase.starts_with?("::ffff:")
      ipv4_str = address.downcase.sub("::ffff:", "")
      begin
        ipv4 = Socket::IPAddress.new(ipv4_str, DNS_RESOLVE_PORT)
        ipv4.private? || ipv4.loopback? || blocked_ipv4?(ipv4)
      rescue ex
        Log.debug { "ipv6_mapped_ipv4_blocked? failed: #{ex.message}" }
        false
      end
    rescue ex
      Log.debug { "ipv6_mapped_ipv4_blocked? failed: #{ex.message}" }
      false
    end

    # Check if an IPv4 address falls within any blocked CIDR range.
    # Uses BLOCKED_IPV4_RANGES for data-driven matching.
    private def self.blocked_ipv4?(ip_address : Socket::IPAddress) : Bool
      octets = ipv4_octets(ip_address)
      return false unless octets && octets.size == 4
      ip_int = (octets[0].to_u32 << 24) | (octets[1].to_u32 << 16) | (octets[2].to_u32 << 8) | octets[3].to_u32
      BLOCKED_IPV4_RANGES.any? do |(prefix, mask_len, _)|
        mask = mask_len == 0 ? 0_u32 : ~(0xFFFFFFFF_u32 >> mask_len)
        (ip_int & mask) == (prefix & mask)
      end
    end

    private def self.ipv4_octets(ip_address : Socket::IPAddress) : Array(Int32)?
      address = ip_address.address
      return if address.includes?(":")
      address.split(".").map(&.to_i)
    rescue ex
      Log.debug { "ipv4_octets failed: #{ex.message}" }
      nil
    end
  end
end
