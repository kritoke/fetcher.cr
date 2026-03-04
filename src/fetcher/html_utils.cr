require "html"

module Fetcher
  module HTMLUtils
    ALLOWED_SCHEMES = {"http", "https"}
    BLOCKED_HOSTS   = {"localhost", "127.0.0.1", "0.0.0.0", "[::1]"}

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

        true
      rescue
        false
      end
    end

    def self.safe_url(url : String?) : String
      return "#" unless validate_url(url)
      url.to_s
    end
  end
end
