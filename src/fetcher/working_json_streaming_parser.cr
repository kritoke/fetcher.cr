require "json"
require "./entry"
require "./result"
require "./reddit"
require "./json_feed"
require "./streaming_error_handling"

module Fetcher
  # JSON streaming parser that uses existing parsers but provides streaming interface
  class WorkingJSONStreamingParser
    def initialize(@limit : Int32 = 100)
    end

    def parse_entries(io : IO, limit : Int32? = nil, config : RequestConfig? = nil) : Array(Entry)
      actual_limit = limit || @limit
      
      check_memory_limit(io, config)
      
      json_string = io.gets_to_end
      
      if json_string.includes?("reddit.com")
        Fetcher::Reddit.parse_reddit_response(json_string, actual_limit)
      elsif json_string.includes?("jsonfeed")
        parser = Fetcher::JSONFeedParser.new
        parser.parse_entries(json_string, actual_limit)
      else
        begin
          parser = Fetcher::JSONFeedParser.new
          entries = parser.parse_entries(json_string, actual_limit)
          return entries unless entries.empty?
        rescue
        end
        
        begin
          Fetcher::Reddit.parse_reddit_response(json_string, actual_limit)
        rescue
          [] of Entry
        end
      end
    rescue ex : StreamingErrorHandling::MemoryLimitExceeded
      raise ex
    rescue ex : JSON::ParseException
      [] of Entry
    end

    private def check_memory_limit(io : IO, config : RequestConfig?)
      return unless config
      
      if io.responds_to?(:size) && io.size > config.max_streaming_memory
        raise StreamingErrorHandling::MemoryLimitExceeded.new(
          "Feed size (#{io.size} bytes) exceeds memory limit (#{config.max_streaming_memory} bytes)"
        )
      end
    end
  end
end
