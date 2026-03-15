require "xml"
require "json"

module Fetcher
  # Base module for streaming feed parsers using pull parser architecture
  module StreamingParser
    # MIME type dispatcher to route feeds to appropriate streaming parser
    def self.detect_feed_type(content_type : String?, url : String) : Symbol
      if content_type
        case content_type.downcase
        when .includes?("application/rss+xml")
          return :rss
        when .includes?("application/atom+xml")
          return :atom
        when .includes?("application/json")
          # Check URL patterns for more specific detection
          if url.includes?("reddit.com")
            return :reddit
          elsif url.ends_with?(".json") || url.includes?("/feed.json") || url.includes?("/feeds/json")
            return :json_feed
          else
            # Default to JSON feed for generic JSON
            return :json_feed
          end
        when .includes?("text/xml"), .includes?("application/xml")
          return :rss
        end
      end

      # Fallback to URL-based detection
      if url.includes?("reddit.com")
        :reddit
      elsif url.ends_with?(".json") || url.includes?("/feed.json") || url.includes?("/feeds/json")
        :json_feed
      elsif url.ends_with?(".xml") || url.includes?("/feed") || url.includes?("/feeds")
        :rss
      else
        # Default to RSS for unknown types
        :rss
      end
    end
  end
end
