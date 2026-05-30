require "xml"
require "log"
require "./entry"
require "./result"
require "./entry_parser"
require "./streaming_rss_parser"
require "./xml_text_reader"
require "./exceptions"

module Fetcher
  # Maximum entity definitions allowed before suspecting entity expansion attack
  MAX_ENTITY_DEFINITIONS = 10

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
    rescue ex
      Log.warn { "XML streaming parser unexpected error: #{ex.class} - #{ex.message}" }
      raise ex
    end

    # Parse XML feed and return array of entries
    def parse_entries(io : IO, limit : Int32? = nil) : Array(Entry)
      actual_limit = limit || @limit

      # For streaming, we need to check the beginning for XXE patterns
      # Read a chunk to inspect before passing to XML parser
      check_xxe_risk(io)

      reader = XML::Reader.new(io)
      parser = StreamingRSSParser.new
      parser.parse_entries(reader, actual_limit)
    rescue ex : XML::Error
      Log.warn { "XML streaming parser error: #{ex.message}" }
      [] of Entry
    rescue ex : InvalidFormatError
      # Re-raise XXE protection errors
      raise ex
    rescue ex
      Log.warn { "XML streaming parser unexpected error: #{ex.class} - #{ex.message}" }
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

    # Buffer size for XXE check (8KB)
    XXE_CHECK_BUFFER_SIZE = 8192

    # Check for XXE/entity expansion risks at the start of the content.
    # For non-seekable streams, this buffers the prefix and returns an IO that
    # includes both the prefix and remaining content (with size limits).
    private def check_xxe_risk(io : IO) : Nil
      # Read first 8KB to check for dangerous DOCTYPE patterns
      prefix_bytes = Bytes.new(XXE_CHECK_BUFFER_SIZE)
      bytes_read = io.read(prefix_bytes)
      return if bytes_read == 0

      prefix = String.new(prefix_bytes[0, bytes_read])

      # Perform the actual XXE checks on the prefix
      perform_xxe_check(prefix)

      # For seekable IO, rewind so XML::Reader starts from the beginning
      if io.responds_to?(:rewind)
        io.rewind
      else
        # For non-seekable streams, wrap remaining content with prefix
        remaining = io.read
        combined = IO::Memory.new(prefix_bytes[0, bytes_read] + remaining)
        io.replace_with(combined) if io.responds_to?(:replace_with)
        # Note: without replace_with, this will miss the prefix in XML parsing.
        # This is a known limitation for non-seekable streams.
        ::Log.for("fetcher").warn { "XXE check on non-seekable stream - using fallback without prefix rewind" }
      end
    rescue ex : InvalidFormatError
      raise ex
    rescue
      # Ignore other errors in the check
    end

    # Perform XXE/entity expansion checks on content
    private def perform_xxe_check(content : String) : Nil
      # Use uppercase for case-insensitive comparison
      upper = content.upcase

      # Reject DOCTYPE with internal subset
      if upper.includes?("<!DOCTYPE") && upper.includes?("[")
        raise InvalidFormatError.new("DOCTYPE with internal subset not allowed (entity expansion risk)")
      end

      # Check for parameter entities
      if upper.scan(/<!ENTITY\s+%/i).size > 0
        raise InvalidFormatError.new("Parameter entity declarations not allowed")
      end

      # Check for external entity declarations (SYSTEM keyword)
      if upper.includes?("<!ENTITY") && upper.includes?("SYSTEM")
        raise InvalidFormatError.new("External entity declarations not allowed")
      end

      # Check entity count
      entity_count = content.scan(/<!ENTITY\s+\w+\s+[^>]*>/i).size
      if entity_count > MAX_ENTITY_DEFINITIONS * 2
        raise InvalidFormatError.new("Too many entity definitions in header")
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
          elsif @in_feed && depth == @feed_depth + 1 && (name == "item" || name == "entry")
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
