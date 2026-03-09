require "html"
require "./url_validator"

module Fetcher
  module HTMLUtils
    def self.sanitize_text(text : String?, default : String = "") : String
      return default if text.nil? || text.empty?
      HTML.unescape(text.strip).presence || default
    end

    def self.sanitize_link(link : String?, default : String = "#") : String
      link.try(&.strip).presence || default
    end

    def self.safe_url(url : String?) : String
      URLValidator.safe_url(url)
    end
  end
end
