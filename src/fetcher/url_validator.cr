require "uri"
require "socket"

module Fetcher
  module URLValidator
    ALLOWED_SCHEMES = {"http", "https"}

    # Standard private and reserved IP ranges that should be blocked for SSRF protection
    LINK_LOCAL_IPV4 = "169.254.0.0/16"
    LINK_LOCAL_IPV6 = "fe80::/10"

    def self.valid?(url : String?) : Bool
      return false if url.nil? || url.empty?

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

    private def self.validate_uri(uri : URI) : Bool
      # Validate scheme
      scheme = uri.scheme.try(&.downcase)
      return false unless scheme && ALLOWED_SCHEMES.includes?(scheme)

      # Validate host
      host = uri.host
      return false if host.nil? || host.empty?

      # Handle IPv6 addresses with brackets
      clean_host = host
      if host.starts_with?("[") && host.ends_with?("]")
        clean_host = host[1..-2]
      end

      # Block localhost and similar hosts
      if clean_host.downcase == "localhost" ||
         clean_host.downcase.ends_with?(".localhost") ||
         clean_host == "0.0.0.0" ||
         clean_host == "::" # IPv6 unspecified address
        return false
      end

      # Try to validate as IP address
      begin
        ip_address = Socket::IPAddress.new(clean_host, 80)

        # Block private IPs
        return false if ip_address.private?

        # Block loopback IPs
        return false if ip_address.loopback?

        # Block link-local IPs
        return false if link_local?(ip_address)
      rescue Socket::Error
        # Not a valid IP address - treat as hostname (allowed)
        # Hostnames will be resolved by DNS later, which is handled by the HTTP client
      end

      true
    end

    private def self.link_local?(ip_address : Socket::IPAddress) : Bool
      address = ip_address.address
      if address.includes?(":")
        # IPv6 address
        # Check IPv6 link-local (fe80::/10)
        address.downcase.starts_with?("fe80:") || address.downcase.starts_with?("fe8")
      else
        # IPv4 address
        # Check IPv4 link-local (169.254.0.0/16)
        parts = address.split(".").map(&.to_i)
        parts.size == 4 && parts[0] == 169 && parts[1] == 254
      end
    rescue
      false
    end
  end
end
