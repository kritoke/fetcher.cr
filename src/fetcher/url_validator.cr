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
    @@validation_ttl = 30.seconds

    def self.clear_validated_ips : Nil
      @@validation_lock.synchronize do
        @@validated_ips.clear
      end
    end

    def self.register_validated_ip(host : String, ip : Socket::IPAddress) : Nil
      @@validation_lock.synchronize do
        @@validated_ips[host] = ValidatedEntry.new(ip, Time.utc)
      end
    end

    def self.cleanup_expired_validations(expiry : Time::Span? = nil) : Nil
      ttl = expiry || @@validation_ttl
      now = Time.utc
      @@validation_lock.synchronize do
        @@validated_ips.reject! { |_, entry| (now - entry.timestamp) > ttl }
      end
    end

    def self.check_dns_rebinding(host : String, current_ip : Socket::IPAddress) : Bool
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
        validate_uri(uri)
      rescue URI::Error
        false
      end
    end

    def self.safe_url(url : String?) : String
      return "#" unless valid?(url)
      url.to_s
    end

    def self.resolve_and_validate(url : String) : Bool
      uri = URI.parse(url)
      return false unless validate_uri(uri)

      host = uri.host
      return true if host.nil? || host.empty?
      return true unless looks_like_ip?(host)

      begin
        addr_info = Socket::Addrinfo.resolve(host, "80", type: Socket::Type::STREAM, protocol: Socket::Protocol::TCP)
        addr_info.each do |addr|
          if addr.family == Socket::Family::INET || addr.family == Socket::Family::INET6
            ip_address = addr.ip_address
            return false if blocked_ip?(ip_address)
          end
        end
        addr_info.each do |addr|
          if addr.family == Socket::Family::INET || addr.family == Socket::Family::INET6
            ip_address = addr.ip_address
            register_validated_ip(host, ip_address)
            return true
          end
        end
        true
      rescue Exception
        true
      end
    end

    def self.validate_connected_ip(host : String, connected_ip : Socket::IPAddress) : Bool
      check_dns_rebinding(host, connected_ip)
    end

    def self.valid_redirect?(redirect_url : String) : Bool
      valid?(redirect_url) && resolve_and_validate(redirect_url)
    end

    private def self.validate_uri(uri : URI) : Bool
      scheme = uri.scheme.try(&.downcase)
      return false unless scheme && ALLOWED_SCHEMES.includes?(scheme)

      host = uri.host
      return false if host.nil? || host.empty?

      clean_host = clean_ipv6_host(host)
      return false if block_localhost?(clean_host)

      !looks_like_ip?(clean_host) || validate_ip_address(clean_host)
    end

    private def self.looks_like_ip?(host : String) : Bool
      return false if host.empty?

      if host.starts_with?("[")
        return true
      end

      first_char = host[0]
      return false unless first_char.ascii_number?

      host.each_char do |c|
        unless c.ascii_number? || c == '.' || c == ':'
          return false
        end
      end
      true
    end

    private def self.clean_ipv6_host(host : String) : String
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

    private def self.validate_ip_address(host : String) : Bool
      ip_address = Socket::IPAddress.new(host, 80)
      !blocked_ip?(ip_address)
    rescue Socket::Error
      true
    end

    private def self.blocked_ip?(ip_address : Socket::IPAddress) : Bool
      ip_address.private? || ip_address.loopback? || link_local?(ip_address) ||
        ipv6_unique_local?(ip_address) || ipv6_site_local?(ip_address) ||
        ipv6_mapped_ipv4_private?(ip_address)
    end

    # Enhanced IPv6 link-local detection with proper IP address parsing
    private def self.link_local?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      if address.includes?(":")
        # IPv6 address - check link-local (fe80::/10)
        # Simplified check: starts with "fe" followed by 8-f
        downcase = address.downcase
        if downcase.starts_with?("fe")
          second_char = downcase[2]?
          if second_char
            return "89abcdef".includes?(second_char)
          end
        end
        false
      else
        # IPv4 address - check IPv4 link-local (169.254.0.0/16)
        parts = address.split(".").map(&.to_i)
        parts.size == 4 && parts[0] == 169 && parts[1] == 254
      end
    rescue
      false
    end

    # IPv6 unique local addresses (fc00::/7) - RFC 4193
    private def self.ipv6_unique_local?(ip_address : Socket::IPAddress) : Bool
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
    private def self.ipv6_site_local?(ip_address : Socket::IPAddress) : Bool
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
    private def self.ipv6_mapped_ipv4_private?(ip_address : Socket::IPAddress) : Bool
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
  end
end
