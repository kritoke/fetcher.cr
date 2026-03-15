require "./buffer_pool"

module Fetcher
  # Adaptive buffer sizing for optimal streaming performance
  module AdaptiveBuffer
    @@default_sizes = {
      rss:      16384,
      atom:     16384,
      json:     8192,
      jsonfeed: 8192,
      reddit:   8192,
      html:     16384,
      default:  16384,
    }

    def self.buffer_size_for(content_type : String, content_length : Int64? = nil) : Int
      type = detect_feed_type(content_type)
      base_size = @@default_sizes[type]

      if content_length && content_length > 1_000_000
        (base_size * 2).clamp(8192, 65536)
      else
        base_size
      end
    end

    def self.detect_feed_type(content_type : String) : Symbol
      ct = content_type.downcase
      case
      when ct.includes?("xml"), ct.includes?("rss"), ct.includes?("atom")
        ct.includes?("json") ? :json : :rss
      when ct.includes?("json") || ct.includes?("feed")
        :jsonfeed
      when ct.includes?("reddit")
        :reddit
      when ct.includes?("html")
        :html
      else
        :default
      end
    end

    def self.set_default_size(type : Symbol, size : Int)
      @@default_sizes[type] = size
    end
  end
end
