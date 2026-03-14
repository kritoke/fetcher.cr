require "json"
require "./entry"
require "./result"
require "./reddit"
require "./json_feed"

module Fetcher
  # JSON streaming parser that uses existing parsers but provides streaming interface
  class WorkingJSONStreamingParser
    def initialize(@limit : Int32 = 100)
    end

    def parse_entries(io : IO, limit : Int32? = nil) : Array(Entry)
      actual_limit = limit || @limit
      
      # Read the entire IO into a string (not truly streaming, but provides the interface)
      json_string = io.gets_to_end
      
      # Use existing parsers based on content detection
      if json_string.includes?("reddit.com")
        # Use Reddit parser
        result = Fetcher::Reddit.parse_reddit_response(json_string, actual_limit)
        return result.entries
      elsif json_string.includes?("jsonfeed")
        # Use JSON Feed parser
        parser = Fetcher::JSONFeedParser.new
        return parser.parse_entries(json_string, actual_limit)
      else
        # Try both parsers
        begin
          parser = Fetcher::JSONFeedParser.new
          entries = parser.parse_entries(json_string, actual_limit)
          return entries unless entries.empty?
        rescue
          # Fall back to Reddit parser
          begin
            result = Fetcher::Reddit.parse_reddit_response(json_string, actual_limit)
            return result.entries
          rescue
            return [] of Entry
          end
        end
      end
    end
  end
end
