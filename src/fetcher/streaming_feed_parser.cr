require "xml"
require "json"

module Fetcher
  # Streaming feed parser interface
  abstract class StreamingFeedParser
    # Maximum allowed feed size in bytes (10MB default)
    MAX_FEED_SIZE = 10 * 1024 * 1024

    # Parse feed content with size limit and streaming
    abstract def parse_streaming(io : IO, limit : Int32) : Array(Entry)

    # Helper method to safely read from IO with size limit
    protected def safe_read_with_limit(io : IO, max_size : Int32 = MAX_FEED_SIZE) : String
      buffer = IO::Memory.new
      bytes_read = 0

      while !io.closed? && bytes_read < max_size
        chunk = io.read_bytes(max_size - bytes_read)
        break if chunk.empty?

        buffer.write(chunk)
        bytes_read += chunk.size

        break if bytes_read >= max_size
      end

      if bytes_read >= max_size
        raise InvalidFormatError.new("Feed too large (>#{max_size / (1024 * 1024)}MB)")
      end

      String.new(buffer.to_slice)
    end

    # Helper method to create pull parser with size limit
    protected def create_xml_pull_parser(io : IO, max_size : Int32 = MAX_FEED_SIZE) : XML::PullParser
      xml_string = safe_read_with_limit(io, max_size)
      XML::PullParser.new(xml_string)
    end

    # Helper method to create JSON pull parser with size limit
    protected def create_json_pull_parser(io : IO, max_size : Int32 = MAX_FEED_SIZE) : JSON::PullParser
      json_string = safe_read_with_limit(io, max_size)
      JSON::PullParser.new(json_string)
    end
  end
end
