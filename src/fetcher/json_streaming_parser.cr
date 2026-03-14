require "json"
require "./entry"
require "./result"
require "./time_parser"

module Fetcher
  # JSON streaming parser using JSON::PullParser with lazy iterator pattern
  class JSONStreamingParser
    def initialize(@limit : Int32 = 100)
      @entries_parsed = 0
    end

    # Parse JSON feed and return lazy iterator
    def parse(io : IO) : JSONStreamingIterator
      JSONStreamingIterator.new(io, @limit)
    end

    # Parse JSON feed and return array (for compatibility)
    def parse_entries(io : IO, limit : Int32? = nil) : Array(Entry)
      actual_limit = limit || @limit
      parse(io).to_a(actual_limit)
    end
  end

  # Lazy iterator for JSON streaming parser
  class JSONStreamingIterator < EntryIterator
    def initialize(@io : IO, @limit : Int32)
      super()
      @pull = JSON::PullParser.new(@io)
      @entries_parsed = 0
      @is_reddit = false
      @is_json_feed = false
    end

    protected def next_entry : Entry?
      return nil if @entries_parsed >= @limit

      # Determine feed type on first call
      unless @is_reddit || @is_json_feed
        determine_feed_type
      end

      if @is_reddit
        return next_reddit_entry
      elsif @is_json_feed  
        return next_json_feed_entry
      else
        # Unknown JSON format, skip
        return nil
      end
    end

    private def determine_feed_type
      # Peek at JSON structure to determine type
      begin
        @pull.read_object do |key|
          if key == "data"
            # Likely Reddit
            @pull.read_object do |data_key|
              if data_key == "children"
                @is_reddit = true
                break
              else
                @pull.skip
              end
            end
          elsif key == "version" && @pull.read_string.includes?("jsonfeed")
            # JSON Feed
            @is_json_feed = true
            break
          else
            @pull.skip
          end
        end
      rescue
        # If we can't determine type, leave both as false
      end

      # Reset pull parser to beginning
      @pull = JSON::PullParser.new(@io)
    end

    private def next_reddit_entry : Entry?
      # Navigate to children array
      @pull.read_object do |key|
        if key == "data"
          @pull.read_object do |data_key|
            if data_key == "children"
              @pull.read_array do
                # We're now in the array of posts
                return parse_reddit_post
              end
            else
              @pull.skip
            end
          end
        else
          @pull.skip
        end
      end

      nil
    end

    private def next_json_feed_entry : Entry?
      @pull.read_object do |key|
        if key == "items"
          @pull.read_array do
            # We're now in the items array
            return parse_json_feed_item
          end
        else
          @pull.skip
        end
      end

      nil
    end

    private def parse_reddit_post : Entry?
      # This is a simplified version - will be expanded later
      # For now, return nil to focus on infrastructure
      nil
    end

    private def parse_json_feed_item : Entry?
      # This is a simplified version - will be expanded later  
      # For now, return nil to focus on infrastructure
      nil
    end
  end
end
