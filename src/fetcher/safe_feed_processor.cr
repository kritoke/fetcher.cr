require "xml"
require "json"

module Fetcher
  # Safe feed processor with memory limits and size validation
  module SafeFeedProcessor
    # Maximum allowed feed size in bytes (10MB default)
    MAX_FEED_SIZE = 10 * 1024 * 1024

    # Process feed content with size validation
    def self.process_feed(content : String, limit : Int32, &block : String -> Array(Entry)) : Array(Entry)
      # Check size before processing
      if content.bytesize > MAX_FEED_SIZE
        raise InvalidFormatError.new("Feed too large (>#{MAX_FEED_SIZE / (1024 * 1024)}MB)")
      end

      # Process the feed
      block.call(content)
    end

    # Process XML feed with streaming parser and size validation
    def self.process_xml_feed_streaming(content : String, limit : Int32, &block : XML::Reader -> Array(Entry)) : Array(Entry)
      if content.bytesize > MAX_FEED_SIZE
        raise InvalidFormatError.new("Feed too large (>#{MAX_FEED_SIZE / (1024 * 1024)}MB)")
      end

      begin
        reader = XML::Reader.new(content)
        block.call(reader)
      rescue ex : XML::Error
        raise InvalidFormatError.new("XML parsing error: #{ex.message}")
      end
    end

    # Process JSON feed with size validation (supports pull parsing)
    def self.process_json_feed(content : String, limit : Int32, &block : String -> Array(Entry)) : Array(Entry)
      if content.bytesize > MAX_FEED_SIZE
        raise InvalidFormatError.new("Feed too large (>#{MAX_FEED_SIZE / (1024 * 1024)}MB)")
      end

      begin
        # Use string for now (can optimize with pull parser later if needed)
        block.call(content)
      rescue ex : JSON::ParseException
        raise InvalidFormatError.new("JSON parsing error: #{ex.message}")
      end
    end
  end
end
