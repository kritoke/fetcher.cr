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
      parse(io).to_a(actual_limit)
    end
  end

  class JSONStreamingIterator < EntryIterator
    @parser : RedditJSONParser | JSONFeedStreamingParser | Nil

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
        return nil unless @parser
      end

      entry = @parser.as(RedditJSONParser | JSONFeedStreamingParser).next_entry(@pull)
      if entry
        @entries_parsed += 1
      end
      entry
    end

    private def determine_feed_type
      begin
        @pull.read_object do |key|
          if key == "data"
            @pull.read_object do |data_key|
              if data_key == "children"
                @parser = RedditJSONParser.new(@limit)
                break
              else
                @pull.skip
              end
            end
          elsif key == "version" && @pull.read_string.includes?("jsonfeed")
            @parser = JSONFeedStreamingParser.new(@limit)
            break
          else
            @pull.skip
          end
        end
      rescue ex
        ::Log.for("fetcher.streaming").debug { "Failed to determine JSON feed type: #{ex.class} - #{ex.message}" }
      end

      if @io.responds_to?(:rewind)
        @io.rewind
        @pull = JSON::PullParser.new(@io)
      else
        ::Log.for("fetcher.streaming").warn { "JSON streaming parser received non-seekable IO; type detection consumed data and cannot be rewound" }
      end
    end
  end
end
