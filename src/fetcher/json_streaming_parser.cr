require "json"
require "./entry"
require "./result"
require "./time_parser"
require "./link_resolver"
require "./reddit_json_parser"
require "./json_feed_streaming_parser"

module Fetcher
  class JSONStreamingParser
    def initialize(@limit : Int32 = 100)
      @entries_parsed = 0
    end

    def parse(io : IO) : JSONStreamingIterator
      JSONStreamingIterator.new(io, @limit)
    end

    def parse_entries(io : IO, limit : Int32? = nil) : Array(Entry)
      actual_limit = limit || @limit
      parse(io).collect(actual_limit)
    end
  end

  class JSONStreamingIterator < EntryIterator
    @parser : RedditJSONParser | JSONFeedStreamingParser?

    def initialize(@io : IO, @limit : Int32)
      super()
      @pull = JSON::PullParser.new(@io)
      @entries_parsed = 0
      @parser = nil
    end

    protected def next_entry : Entry?
      return if @entries_parsed >= @limit

      unless @parser
        determine_feed_type
        return unless @parser
      end

      entry = @parser.as(RedditJSONParser | JSONFeedStreamingParser).next_entry(@pull)
      if entry
        @entries_parsed += 1
      end
      entry
    end

    private def determine_feed_type
      detect_parser_type

      if @io.responds_to?(:rewind)
        @io.rewind
        @pull = JSON::PullParser.new(@io)
      else
        ::Log.for("fetcher.streaming").warn { "JSON streaming parser received non-seekable IO; type detection consumed data and cannot be rewound - falling back to DOM parser" }
        raise MemoryLimitExceeded.new("Non-seekable IO cannot be used with streaming JSON parser after type detection")
      end
    end

    private def detect_parser_type
      @pull.read_object do |key|
        case key
        when "data"
          detect_reddit_parser
        when "version"
          if @pull.read_string.includes?("jsonfeed")
            @parser = JSONFeedStreamingParser.new(@limit)
            break
          end
        else
          @pull.skip
        end
      end
    rescue ex
      ::Log.for("fetcher.streaming").warn { "Failed to determine JSON feed type: #{ex.class} - #{ex.message}" }
    end

    private def detect_reddit_parser
      @pull.read_object do |data_key|
        if data_key == "children"
          @parser = RedditJSONParser.new(@limit)
          break
        else
          @pull.skip
        end
      end
    end
  end
end
