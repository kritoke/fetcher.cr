require "html"
require "sanitize"
require "./attachment"

module Fetcher
  record Entry,
    title : String,
    url : String,
    source_type : String,
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
                    source_type : String,
                    content : String = "",
                    content_html : String? = nil,
                    author : String? = nil,
                    author_url : String? = nil,
                    published_at : Time? = nil,
                    categories : Array(String) = [] of String,
                    attachments : Array(Attachment) = [] of Attachment,
                    version : String? = nil) : Entry
      safe_url = HTMLUtils.validate_url(url) ? url : "#"
      new(title: title, url: safe_url, source_type: source_type,
        content: sanitize_content(content), content_html: content_html,
        author: author, author_url: author_url,
        published_at: published_at,
        categories: categories, attachments: attachments,
        version: version)
    end

    def self.sanitize_title(title : String?) : String
      return "Untitled" if title.nil? || title.empty?
      HTML.unescape(title.strip).presence || "Untitled"
    end

    def self.sanitize_content(content : String) : String
      return "" if content.empty?
      begin
        sanitizer = Sanitize::Policy::HTMLSanitizer.common
        sanitizer.process(content).to_s
      rescue
        content
      end
    end
  end
end
