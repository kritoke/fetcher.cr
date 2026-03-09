require "html"
require "sanitize"
require "./attachment"
require "./source_type"
require "./url_validator"
require "./entry_factory"

module Fetcher
  record Entry,
    title : String,
    url : String,
    source_type : SourceType,
    content : String = "",
    content_html : String? = nil,
    author : String? = nil,
    author_url : String? = nil,
    published_at : Time? = nil,
    categories : Array(String) = [] of String,
    attachments : Array(Attachment) = [] of Attachment,
    version : String? = nil do
    def self.create(title : String,
                    url : String,
                    source_type : SourceType,
                    content : String = "",
                    content_html : String? = nil,
                    author : String? = nil,
                    author_url : String? = nil,
                    published_at : Time? = nil,
                    categories : Array(String) = [] of String,
                    attachments : Array(Attachment) = [] of Attachment,
                    version : String? = nil) : Entry
      EntryFactory.create(
        title: title,
        url: url,
        source_type: source_type,
        content: content,
        content_html: content_html,
        author: author,
        author_url: author_url,
        published_at: published_at,
        categories: categories,
        attachments: attachments,
        version: version
      )
    end

    def self.sanitize_title(title : String?) : String
      return "Untitled" if title.nil? || title.empty?
      HTML.unescape(title.strip).presence || "Untitled"
    end
  end
end
