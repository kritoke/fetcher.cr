require "time"
require "html"
require "./url_validator"

module Fetcher
  module HTMLUtils
    # Maximum allowed length for unescaped text to prevent entity explosion attacks
    MAX_UNESCAPE_BYTESIZE = 100_000 # 100KB

    def self.sanitize_text(text : String?, default : String = "") : String
      return default if text.nil? || text.empty?
      unescaped = HTML.unescape(text.strip)
      # Prevent CPU exhaustion from deeply nested entities
      return default if unescaped.bytesize > MAX_UNESCAPE_BYTESIZE
      unescaped.presence || default
    end

    def self.sanitize_link(link : String?, default : String = "#") : String
      link.try(&.strip).presence || default
    end

    def self.safe_url(url : String?) : String
      URLValidator.safe_url(url)
    end
  end
end
