require "html"

module Fetcher
  module HTMLUtils
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
        uri.scheme == "http" || uri.scheme == "https"
      rescue
        false
      end
    end
  end
end
