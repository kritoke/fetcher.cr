require "uri"
require "socket"

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

    @@validated_ips = {} of String => ValidatedEntry
    @@validation_lock = Mutex.new
    @@validation_ttl = 5.seconds
    MAX_VALIDATED_ENTRIES = 50_000

    def self.clear_validated : Nil
      @@validation_lock.synchronize do
        @@validated_ips.clear
      end
    end

    def self.register_ip(host : String, ip : Socket::IPAddress) : Nil
      @@validation_lock.synchronize do
        enforce_validated_limit
        @@validated_ips[host] = ValidatedEntry.new(ip, Time.utc)
      end
    end

    def self.purge_expired(expiry : Time::Span? = nil) : Nil
      ttl = expiry || @@validation_ttl
      now = Time.utc
      @@validation_lock.synchronize do
        @@validated_ips.reject! { |_, entry| (now - entry.timestamp) > ttl }
      end
    end

    private def self.enforce_validated_limit : Nil
      return if @@validated_ips.size < MAX_VALIDATED_ENTRIES
      now = Time.utc
      @@validated_ips.reject! { |_, entry| (now - entry.timestamp) > @@validation_ttl }
      return if @@validated_ips.size < MAX_VALIDATED_ENTRIES
      sorted = @@validated_ips.to_a.sort_by { |_, entry| entry.timestamp }
      excess = sorted.first(@@validated_ips.size - MAX_VALIDATED_ENTRIES + 1000)
      excess.each { |key, _| @@validated_ips.delete(key) }
    end

    def self.check_rebinding(host : String, current_ip : Socket::IPAddress) : Bool
      @@validation_lock.synchronize do
        if entry = @@validated_ips[host]?
          if (Time.utc - entry.timestamp) <= @@validation_ttl
            return entry.ip == current_ip
          else
            @@validated_ips.delete(host)
          end
        end
      end
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
      url.to_s
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
        valid_ips = [] of Socket::IPAddress

        addr_info.each do |addr|
          if addr.family == Socket::Family::INET || addr.family == Socket::Family::INET6
            ip_address = addr.ip_address
            return false if blocked_ip?(ip_address)
            valid_ips << ip_address
          end
        end

        valid_ips.each do |ip|
          register_ip(host, ip)
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
          when ".."    then acc.pop?
          when ".", "" then nil
          else              acc << segment
          end
          acc
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

    def self.looks_like_ip?(host : String) : Bool
      return false if host.empty?

      if host.starts_with?("[")
        return true
      end

      if host.includes?(":")
        return true
      end

      first_char = host[0]
      return false unless first_char.ascii_number?

      valid_ip_chars = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', ':', 'a', 'b', 'c', 'd', 'e', 'f', 'A', 'B', 'C', 'D', 'E', 'F'}
      host.each_char do |char|
        unless valid_ip_chars.includes?(char)
          return false
        end
      end
      true
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

    private VALID_HEX_CHARS = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'}

    private def self.link_local?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      if address.includes?(":")
        downcase = address.downcase
        if downcase.starts_with?("fe")
          second_char = downcase[2]?
          return false unless second_char
          return false unless VALID_HEX_CHARS.includes?(second_char)
          second_nibble = second_char.to_i(16)
          second_nibble >= 8 && second_nibble <= 15
        else
          false
        end
      else
        parts = address.split(".").map(&.to_i)
        parts.size == 4 && parts[0] == 169 && parts[1] == 254
      end
    rescue
      false
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

    # IPv6 site-local addresses (deprecated) - RFC 3874
    private def self.ipv6_site?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      if address.includes?(":")
        # IPv6 site-local addresses (fec0::/10) - deprecated but still in use
        address.downcase.starts_with?("fec") ||
          address.downcase.starts_with?("fed") ||
          address.downcase.starts_with?("fee") ||
          address.downcase.starts_with?("fef")
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

    # Carrier-Grade NAT (100.64.0.0/10) - RFC 6598
    private def self.cgnat?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      return false if address.includes?(":")
      parts = address.split(".").map(&.to_i)
      parts.size == 4 && parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127
    rescue
      false
    end

    # Network Benchmark Testing (198.18.0.0/15) - RFC 2544
    private def self.benchmark?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      return false if address.includes?(":")
      parts = address.split(".").map(&.to_i)
      parts.size == 4 && parts[0] == 198 && (parts[1] == 18 || parts[1] == 19)
    rescue
      false
    end

    # Multicast (224.0.0.0/4)
    private def self.multicast?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      return false if address.includes?(":")
      parts = address.split(".").map(&.to_i)
      parts.size == 4 && parts[0] >= 224 && parts[0] <= 239
    rescue
      false
    end

    # Reserved / Future Use (240.0.0.0/4)
    private def self.reserved?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      return false if address.includes?(":")
      parts = address.split(".").map(&.to_i)
      parts.size == 4 && parts[0] >= 240
    rescue
      false
    end

    # Current Network (0.0.0.0/8)
    private def self.current_network?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      return false if address.includes?(":")
      parts = address.split(".").map(&.to_i)
      parts.size == 4 && parts[0] == 0
    rescue
      false
    end
  end
end
