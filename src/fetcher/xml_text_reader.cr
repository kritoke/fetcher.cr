module Fetcher
  module XMLTextReader
    MAX_XML_DEPTH  =      1000
    MAX_ITERATIONS = 1_000_000

    def self.read_text_content(reader : XML::Reader) : String
      if reader.node_type == XML::Reader::Type::ELEMENT && reader.empty_element?
        return ""
      end

      target_depth = reader.depth
      builder = String::Builder.new
      iterations = 0
      while reader.read
        iterations += 1
        if iterations > MAX_ITERATIONS
          raise MemoryLimitExceeded.new("XML text content exceeded maximum iterations (possible malformed XML)")
        end
        case reader.node_type
        when XML::Reader::Type::TEXT, XML::Reader::Type::CDATA
          builder << reader.value
        when XML::Reader::Type::END_ELEMENT
          break if reader.depth == target_depth
        end
      end
      builder.to_s
    end
  end
end
