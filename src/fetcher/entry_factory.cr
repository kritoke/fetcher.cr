require "./entry"
require "./url_validator"

module Fetcher
  # Factory for creating validated Entry instances
  class EntryFactory
    # Cache sanitizers at class level to avoid repeated allocation.
    # Creating Sanitize::Policy::HTMLSanitizer.common on every call is expensive.
    @@_sanitizer = Sanitize::Policy::HTMLSanitizer.common
    @@_content_sanitizer = Sanitize::Policy::HTMLSanitizer.common

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
      comment_url : String? = nil,
      commentary_url : String? = nil,
      is_discussion_url : Bool = false,
    ) : Entry
      safe_url = URLValidator.valid?(url) ? url : "#"
      safe_comment_url = sanitize_secondary_url(comment_url)
      safe_commentary_url = sanitize_secondary_url(commentary_url)
      safe_author_url = sanitize_secondary_url(author_url)
      safe_attachments = attachments.map { |a| sanitize_attachment(a) }
      safe_content_html = sanitize_content_html(content_html)

      Entry.new(
        title: title,
        url: safe_url,
        source_type: source_type,
        content: sanitize(content),
        content_html: safe_content_html,
        author: author,
        author_url: safe_author_url,
        published_at: published_at,
        categories: categories,
        attachments: safe_attachments,
        version: version,
        comment_url: safe_comment_url,
        commentary_url: safe_commentary_url,
        is_discussion_url: is_discussion_url
      )
    end

    private def self.sanitize_secondary_url(url : String?) : String?
      return if url.nil? || url.empty?
      URLValidator.safe_scheme?(url) ? url : nil
    end

    private def self.sanitize_attachment(attachment : Attachment) : Attachment
      return attachment if URLValidator.safe_scheme?(attachment.url)
      Attachment.new(url: "#", mime_type: attachment.mime_type, title: attachment.title, size_in_bytes: attachment.size_in_bytes, duration_in_seconds: attachment.duration_in_seconds)
    end

    private def self.sanitize_content_html(html : String?) : String?
      return if html.nil? || html.empty?
      begin
        sanitizer = Sanitize::Policy::HTMLSanitizer.common
        result = sanitizer.process(html).to_s
        result.presence
      rescue ex
        ::Log.for("fetcher").warn { "HTML sanitization of content_html failed: #{ex.message}" }
        nil
      end
    end

    private def self.sanitize(content : String) : String
      return "" if content.empty?
      @@_sanitizer.process(content).to_s
    rescue ex
      ::Log.for("fetcher").warn { "HTML sanitization failed: #{ex.message}" }
      ""
    end
  end
end
