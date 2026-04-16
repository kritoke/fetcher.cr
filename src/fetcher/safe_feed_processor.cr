require "xml"
require "json"
require "./config"

module Fetcher
  # Safe feed processor with memory limits and size validation
  module SafeFeedProcessor
    MAX_FEED_SIZE = Config::MAX_FEED_SIZE

    private def self.check_size(content : String) : Nil
      return if content.bytesize <= MAX_FEED_SIZE
      raise InvalidFormatError.new("Feed too large (#{content.bytesize} bytes, max: #{MAX_FEED_SIZE} bytes)")
    end

    def self.process_feed(content : String, limit : Int32, &block : String -> Array(Entry)) : Array(Entry)
      check_size(content)
      block.call(content)
    end

    def self.process_xml_feed_streaming(content : String, limit : Int32, &block : XML::Reader -> Array(Entry)) : Array(Entry)
      check_size(content)
      begin
        reader = XML::Reader.new(content)
        block.call(reader)
      rescue ex : XML::Error
        raise InvalidFormatError.new("XML parsing error: #{ex.message}")
      end
    end

    def self.process_json_feed(content : String, limit : Int32, &block : String -> Array(Entry)) : Array(Entry)
      check_size(content)
      begin
        block.call(content)
      rescue ex : JSON::ParseException
        raise InvalidFormatError.new("JSON parsing error: #{ex.message}")
      end
    end
  end
end
