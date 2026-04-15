require "xml"
require "./entry"
require "./result"
require "./streaming_rss_parser"
require "./xml_text_reader"

module Fetcher
  record FeedMetadata,
    site_link : String? = nil,
    favicon : String? = nil,
    feed_title : String? = nil,
    feed_description : String? = nil,
    feed_language : String? = nil,
    feed_authors : Array(Author) = [] of Author do
    def to_result(entries : Array(Entry)) : Result
      Result.success(
        entries: entries,
        site_link: site_link,
        favicon: favicon,
        feed_title: feed_title,
        feed_description: feed_description,
        feed_language: feed_language,
        feed_authors: feed_authors
      )
    end
  end

  # XML streaming parser using existing StreamingRSSParser with lazy iterator pattern
  class XMLStreamingParser
    def initialize(@limit : Int32 = 100)
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

      # Use lazy iterator to avoid buffering all entries
      iterator = XMLStreamingIterator.new(io, actual_limit)
      entries = iterator.to_a
      metadata = iterator.metadata

      metadata.to_result(entries)
    rescue ex : XML::Error
      error = Error.invalid_format("XML parsing error: #{ex.message}", "streaming")
      Fetcher.error_result(ErrorKind::InvalidFormat, error.message)
    rescue ex : MemoryLimitExceeded
      raise ex
    rescue ex : Exception
      ::Log.for("fetcher").warn { "XML streaming parser unexpected error: #{ex.class} - #{ex.message}" }
      raise ex
    end

    # Parse XML feed and return array of entries
    def parse_entries(io : IO, limit : Int32? = nil) : Array(Entry)
      actual_limit = limit || @limit
      reader = XML::Reader.new(io)
      parser = StreamingRSSParser.new
      parser.parse_entries(reader, actual_limit)
    rescue ex : XML::Error
      ::Log.for("fetcher").warn { "XML streaming parser error: #{ex.message}" }
      [] of Entry
    rescue ex : Exception
      ::Log.for("fetcher").warn { "XML streaming parser unexpected error: #{ex.class} - #{ex.message}" }
      raise ex
    end

    private def check_memory_limit(io : IO, config : RequestConfig?)
      return unless config

      # Check if IO size exceeds memory limit
      if io.responds_to?(:size) && io.size > config.streaming.max_memory
        raise MemoryLimitExceeded.new(
          "Feed size (#{io.size} bytes) exceeds memory limit (#{config.streaming.max_memory} bytes)"
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
      @entries_yielded = 0
      @metadata = FeedMetadata.new
      @in_feed = false
      @feed_depth = 0
    end

    def metadata : FeedMetadata
      @metadata
    end

    protected def next_entry : Entry?
      return if @entries_yielded >= @limit

      while @reader.read
        case @reader.node_type
        when XML::Reader::Type::ELEMENT
          depth = @reader.depth
          name = @reader.name

          if name == "channel" || name == "feed"
            @in_feed = true
            @feed_depth = depth
          elsif @in_feed && depth <= @feed_depth && (name == "item" || name == "entry")
            @entries_yielded += 1
            return @parser.parse_single_entry(@reader)
          elsif @in_feed && depth == @feed_depth + 1
            extract_metadata(name)
          end
        when XML::Reader::Type::END_ELEMENT
          if @reader.name == "channel" || @reader.name == "feed"
            @in_feed = false
          end
        end
      end

      nil
    end

    private def extract_metadata(name : String) : Nil
      case name
      when "title"
        @metadata = @metadata.copy_with(feed_title: read_text_content)
      when "description", "subtitle"
        @metadata = @metadata.copy_with(feed_description: read_text_content)
      when "language"
        @metadata = @metadata.copy_with(feed_language: read_text_content)
      when "icon", "logo"
        @metadata = @metadata.copy_with(favicon: read_text_content)
      when "link"
        if href = @reader["href"]?.try(&.strip).presence
          @metadata = @metadata.copy_with(site_link: @metadata.site_link || href)
        end
      end
    end

    MAX_XML_DEPTH = 1000

    private def read_text_content : String
      XMLTextReader.read_text_content(@reader)
    end
  end
end
