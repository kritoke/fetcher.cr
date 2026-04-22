require "uri"
require "socket"
require "./bounded_registry"
require "./validated_ip_store"

module Fetcher
  module URLValidator
    ALLOWED_SCHEMES = {"http", "https"}
    MAX_URL_LENGTH  = 2048

    # Standard private and reserved IP ranges that should be blocked for SSRF protection
    LINK_LOCAL_IPV4 = "169.254.0.0/16"
    LINK_LOCAL_IPV6 = "fe80::/10"

    # DNS rebinding mitigation: track recently validated hostnames and their IPs
    record ValidatedEntry,
      ip : Socket::IPAddress,
      timestamp : Time

    # Backwards-compatible store. We encapsulate the mutable cache in
    # ValidatedIpStore but keep a class-level default instance so existing
    # call-sites remain functional without signature changes.
    @@validated_store : ValidatedIpStore? = nil
    @@validated_store_lock = Mutex.new

    def self.validated_store
      @@validated_store_lock.synchronize { @@validated_store ||= ValidatedIpStore.new }
    end

    # Legacy compatibility: max_validated_entries method-style accessor for
    # the limit on tracked hostname/IP associations. The default limit is 50,000.
    def self.max_validated_entries : Int32
      50_000
    end

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

    SAFE_SCHEMES      = {"http", "https"}
    DANGEROUS_SCHEMES = {"javascript", "vbscript", "data", "file", "ftp", "jar", "mailto"}

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
    rescue
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
        addr_info = Socket::Addrinfo.resolve(host, "80", type: Socket::Type::STREAM, protocol: Socket::Protocol::TCP)

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
    rescue
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
        Socket::IPAddress.new(host, 80)
        true
      rescue
        # Fallback: if there's a colon it's likely IPv6-ish; if it starts with
        # a digit and matches hex/dot/colon chars, treat as IP-like.
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
      ip_address = Socket::IPAddress.new(host, 80)
      !blocked_ip?(ip_address)
    rescue Socket::Error
      false
    end

    private def self.blocked_ip?(ip_address : Socket::IPAddress) : Bool
      ip_address.private? || ip_address.loopback? || link_local?(ip_address) ||
        ipv6_unique?(ip_address) || ipv6_site?(ip_address) ||
        ipv6_mapped_ipv4?(ip_address) || cgnat?(ip_address) ||
        benchmark?(ip_address) || multicast?(ip_address) ||
        reserved?(ip_address) || current_network?(ip_address)
    end

    private def self.ipv6_site?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      return false unless address.includes?(":")

      downcase = address.downcase
      second_char = downcase[2]?
      return false unless second_char && downcase.starts_with?("fe") && second_char.in?('c', 'd', 'e', 'f')
      true
    rescue
      false
    end

    private def self.link_local?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      if address.includes?(":")
        downcase = address.downcase
        if downcase.starts_with?("fe")
          second_char = downcase[2]?
          return false unless second_char
          second_nibble = second_char.to_i?(16)
          return false unless second_nibble && second_nibble >= 8 && second_nibble <= 15
          true
        else
          false
        end
      else
        return false unless parts = ipv4_octets(ip_address)
        parts.size == 4 && parts[0] == 169 && parts[1] == 254
      end
    end

    # IPv6 unique local addresses (fc00::/7) - RFC 4193
    private def self.ipv6_unique?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      if address.includes?(":")
        # IPv6 unique local addresses (fc00::/7)
        # Covers fc00::/8 and fd00::/8
        address.downcase.starts_with?("fc") || address.downcase.starts_with?("fd")
      else
        false
      end
    rescue
      false
    end

    # IPv6 mapped IPv4 addresses (::ffff:x.x.x.x) - check if mapped IPv4 is private
    private def self.ipv6_mapped_ipv4?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      if address.includes?(":") && address.downcase.starts_with?("::ffff:")
        # IPv6 mapped IPv4 (e.g., ::ffff:192.168.1.1)
        # Extract the IPv4 portion
        ipv4_str = address.downcase.sub("::ffff:", "")
        begin
          ipv4 = Socket::IPAddress.new(ipv4_str, 80)
          ipv4.private? || ipv4.loopback? || link_local?(ipv4)
        rescue
          false
        end
      else
        false
      end
    rescue
      false
    end

    private def self.ipv4_octets(ip_address : Socket::IPAddress) : Array(Int32)?
      address = ip_address.address
      return if address.includes?(":")
      address.split(".").map(&.to_i)
    rescue
      nil
    end

    # Carrier-Grade NAT (100.64.0.0/10) - RFC 6598
    private def self.cgnat?(ip_address : Socket::IPAddress) : Bool
      return false unless parts = ipv4_octets(ip_address)
      parts.size == 4 && parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127
    end

    # Network Benchmark Testing (198.18.0.0/15) - RFC 2544
    private def self.benchmark?(ip_address : Socket::IPAddress) : Bool
      return false unless parts = ipv4_octets(ip_address)
      parts.size == 4 && parts[0] == 198 && (parts[1] == 18 || parts[1] == 19)
    end

    # Multicast (224.0.0.0/4)
    private def self.multicast?(ip_address : Socket::IPAddress) : Bool
      return false unless parts = ipv4_octets(ip_address)
      parts.size == 4 && parts[0] >= 224 && parts[0] <= 239
    end

    # Reserved / Future Use (240.0.0.0/4)
    private def self.reserved?(ip_address : Socket::IPAddress) : Bool
      return false unless parts = ipv4_octets(ip_address)
      parts.size == 4 && parts[0] >= 240
    end

    # Current Network (0.0.0.0/8)
    private def self.current_network?(ip_address : Socket::IPAddress) : Bool
      return false unless parts = ipv4_octets(ip_address)
      parts.size == 4 && parts[0] == 0
    end
  end
end
