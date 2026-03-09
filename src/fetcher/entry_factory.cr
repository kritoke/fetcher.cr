require "./entry"
require "./url_validator"

module Fetcher
  # Factory for creating validated Entry instances
  class EntryFactory
    def self.create(
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
      version : String? = nil,
    ) : Entry
      safe_url = URLValidator.valid?(url) ? url : "#"
      Entry.new(
        title: title,
        url: safe_url,
        source_type: source_type,
        content: sanitize_content(content),
        content_html: content_html,
        author: author,
        author_url: author_url,
        published_at: published_at,
        categories: categories,
        attachments: attachments,
        version: version
      )
    end

    private def self.sanitize_content(content : String) : String
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
