require "html"

module Fetcher
  module HTMLUtils
    ALLOWED_SCHEMES = {"http", "https"}
    BLOCKED_HOSTS   = {"localhost", "127.0.0.1", "0.0.0.0", "[::1]"}
    BLOCKED_DOMAINS = {"localhost"}

    PrivateIPRanges = [
      "127.0.0.0/8",    # Loopback
      "10.0.0.0/8",     # Private Class A
      "172.16.0.0/12",  # Private Class B
      "192.168.0.0/16", # Private Class C
      "169.254.0.0/16", # Link-local
      "::1/128",        # IPv6 loopback
      "fc00::/7",       # IPv6 unique local
      "fe80::/10",      # IPv6 link-local
    ]

    def self.sanitize_text(text : String?, default : String = "") : String
      return default if text.nil? || text.empty?
      HTML.unescape(text.strip).presence || default
    end

    def self.sanitize_link(link : String?, default : String = "#") : String
      link.try(&.strip).presence || default
    end

    def self.validate_url(url : String?) : Bool
      return false if url.nil? || url.empty?

      begin
        uri = URI.parse(url)
        scheme = uri.scheme.try(&.downcase)
        host = uri.host.try(&.downcase)

        return false unless ALLOWED_SCHEMES.includes?(scheme)
        return false if host.nil? || host.empty?
        return false if BLOCKED_HOSTS.any? { |blocked| host == blocked || host.ends_with?(".#{blocked}") }
        return false if BLOCKED_DOMAINS.any? { |domain| host == domain }
        return false if private_ip?(host)

        true
      rescue
        false
      end
    end

    def self.private_ip?(host : String) : Bool
      return false if host.nil? || host.empty?

      begin
        if host.includes?(":")
          ipv6_private_check(host)
        else
          ipv4_private_check(host)
        end
      rescue
        false
      end
    end

    private def self.ipv4_private_check(ip : String) : Bool
      parts = ip.split(".").map(&.to_i)
      return false unless parts.size == 4

      first = parts[0]
      second = parts[1]

      # 127.0.0.0/8 (loopback)
      return true if first == 127

      # 10.0.0.0/8 (private class A)
      return true if first == 10

      # 172.16.0.0/12 (private class B)
      return true if first == 172 && (16..31).includes?(second)

      # 192.168.0.0/16 (private class C)
      return true if first == 192 && second == 168

      # 169.254.0.0/16 (link-local)
      return true if first == 169 && second == 254

      false
    end

    private def self.ipv6_private_check(ip : String) : Bool
      # ::1/128 (loopback)
      return true if ip == "::1"

      # fe80::/10 (link-local)
      return true if ip.starts_with?("fe80:")

      # fc00::/7 (unique local) - simplified check
      return true if ip.starts_with?("fc") || ip.starts_with?("fd")

      false
    end

    def self.safe_url(url : String?) : String
      return "#" unless validate_url(url)
      url.to_s
    end
  end
end
