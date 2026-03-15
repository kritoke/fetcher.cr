require "xml"
require "./entry"
require "./result"
require "./streaming_rss_parser"

module Fetcher
  # Feed metadata extracted during streaming
  struct FeedMetadata
    getter site_link : String?
    getter favicon : String?
    getter feed_title : String?
    getter feed_description : String?
    getter feed_language : String?
    getter feed_authors : Array(Author)

    def initialize(
      @site_link : String? = nil,
      @favicon : String? = nil,
      @feed_title : String? = nil,
      @feed_description : String? = nil,
      @feed_language : String? = nil,
      @feed_authors : Array(Author) = [] of Author,
    )
    end

    # Create success result with this metadata
    def to_result(entries : Array(Entry)) : Result
      ResultBuilder.success(
        entries: entries,
        site_link: @site_link,
        favicon: @favicon,
        feed_title: @feed_title,
        feed_description: @feed_description,
        feed_language: @feed_language,
        feed_authors: @feed_authors
      )
    end
  end

  # XML streaming parser using existing StreamingRSSParser with lazy iterator pattern
  class XMLStreamingParser
    @feed_metadata : FeedMetadata?

    def initialize(@limit : Int32 = 100)
      @entries_parsed = 0
      @feed_metadata = nil
    end

    # Parse XML feed and return lazy iterator
    def parse(io : IO) : XMLStreamingIterator
      XMLStreamingIterator.new(io, @limit)
    end

    # Parse XML feed completely and return Result with metadata
    def parse_complete(io : IO, limit : Int32? = nil, config : RequestConfig? = nil) : Result
      actual_limit = limit || @limit

      # Check memory limit before parsing
      check_memory_limit(io, config)

      # Use existing StreamingRSSParser for now
      reader = XML::Reader.new(io)
      parser = StreamingRSSParser.new
      entries = parser.parse_entries(reader, actual_limit)

      # Create minimal metadata (feed metadata extraction will be added later)
      metadata = FeedMetadata.new
      metadata.to_result(entries)
    rescue ex : XML::Error
      error = Error.invalid_format("XML parsing error: #{ex.message}", "streaming")
      Fetcher.error_result(ErrorKind::InvalidFormat, error.message)
    rescue ex : StreamingErrorHandling::MemoryLimitExceeded
      # Don't fallback for memory issues - raise immediately
      raise ex
    rescue ex : Exception
      # Generic error handling
      error = Error.unknown("Streaming parser error: #{ex.message}", "streaming")
      Fetcher.error_result(ErrorKind::Unknown, error.message)
    end

    # Parse XML feed and return array of entries
    def parse_entries(io : IO, limit : Int32? = nil) : Array(Entry)
      actual_limit = limit || @limit
      reader = XML::Reader.new(io)
      parser = StreamingRSSParser.new
      parser.parse_entries(reader, actual_limit)
    rescue ex : XML::Error
      [] of Entry
    end

    private def check_memory_limit(io : IO, config : RequestConfig?)
      return unless config

      # Check if IO size exceeds memory limit
      if io.responds_to?(:size) && io.size > config.max_streaming_memory
        raise StreamingErrorHandling::MemoryLimitExceeded.new(
          "Feed size (#{io.size} bytes) exceeds memory limit (#{config.max_streaming_memory} bytes)"
        )
      end
    end
  end

  # Lazy iterator wrapper for existing StreamingRSSParser
  class XMLStreamingIterator < EntryIterator
    def initialize(@io : IO, @limit : Int32)
      super()
      @reader = XML::Reader.new(@io)
      @parser = StreamingRSSParser.new
      @entries = nil
      @current_index = 0
    end

    protected def next_entry : Entry?
      # Parse all entries on first call (not truly lazy, but works for now)
      @entries ||= @parser.parse_entries(@reader, @limit)

      if @current_index < @entries.size
        entry = @entries[@current_index]
        @current_index += 1
        entry
      else
        nil
      end
    end
  end
end
