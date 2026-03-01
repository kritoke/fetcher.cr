require "html"

module Fetcher
  record Entry,
    title : String,
    url : String,
    source_type : String,
    content : String = "",
    author : String? = nil,
    published_at : Time? = nil,
    version : String? = nil do
    def self.create(title : String,
                    url : String,
                    source_type : String,
                    content : String = "",
                    author : String? = nil,
                    published_at : Time? = nil,
                    version : String? = nil) : Entry
      new(title: title, url: url, source_type: source_type, content: content,
        author: author, published_at: published_at, version: version)
    end

    def self.sanitize_title(title : String?) : String
      return "Untitled" if title.nil? || title.empty?
      HTML.unescape(title.strip).presence || "Untitled"
    end
  end
end
