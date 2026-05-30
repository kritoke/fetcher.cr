require "json"
require "./entry"
require "./result"
require "./entry_parser"
require "./time_parser"
require "./author"
require "./attachment"
require "./link_resolver"

module Fetcher
  # JSON Feed parser implementation
  class JSONFeedParser < EntryParser
    def parse_entries(data : String, limit : Int32) : Array(Entry)
      parsed = parse_json(data)
      parse_entries(parsed, limit)
    end

    def parse_entries(parsed : JSON::Any, limit : Int32) : Array(Entry)
      version = parsed["version"]?.try(&.as_s)
      raise InvalidFormatError.new("Invalid JSON Feed: missing version") unless version
      raise InvalidFormatError.new("Unsupported JSON Feed version") unless version.starts_with?("https://jsonfeed.org/version/")

      items = parsed["items"]?.try(&.as_a) || [] of JSON::Any
      items.first(limit).compact_map { |item| parse_item(item) }
    end

    def parse_feed_metadata(data : String) : FeedMetadata
      parsed = parse_json(data)
      parse_feed_metadata(parsed)
    end

    def parse_feed_metadata(parsed : JSON::Any) : FeedMetadata
      home_url = parsed["home_page_url"]?.try(&.as_s)
      favicon = parsed["favicon"]?.try(&.as_s)
      icon = parsed["icon"]?.try(&.as_s)
      feed_title = parsed["title"]?.try(&.as_s)
      description = parsed["description"]?.try(&.as_s)
      feed_language = parsed["language"]?.try(&.as_s)

      feed_authors = parse_authors(parsed)

      FeedMetadata.new(
        site_link: home_url,
        favicon: favicon || icon,
        feed_title: feed_title,
        feed_description: description,
        feed_language: feed_language,
        feed_authors: feed_authors,
      )
    end

    private def parse_json(data : String) : JSON::Any
      JSON.parse(data)
    rescue ex : JSON::ParseException
      raise InvalidFormatError.new("JSON parsing error: #{ex.message}")
    end

    private def parse_authors(parsed : JSON::Any) : Array(Author)
      authors_json = parsed["authors"]?.try(&.as_a) || parsed["author"]?.try(&.as_a)
      return [] of Author unless authors_json
      authors_json.compact_map { |json| parse_single_author(json) }
    end

    private def parse_single_author(author_json : JSON::Any) : Author?
      name = author_json["name"]?.try(&.as_s)
      return unless name
      Author.new(
        name: name,
        url: author_json["url"]?.try(&.as_s),
        avatar: author_json["avatar"]?.try(&.as_s)
      )
    end

    private def parse_item(item : JSON::Any) : Entry?
      id = item["id"]?.try(&.to_s)
      return if id.nil? || id.empty?

      Entry.create(
        title: sanitize_item_title(item),
        url: resolve_item_url(item, id),
        source_type: SourceType::JSONFeed,
        content: extract_item_content(item),
        author: extract_item_author(item),
        author_url: extract_item_author_url(item),
        published_at: parse_item_date(item),
        categories: extract_item_tags(item),
        attachments: parse_attachments(item),
        comment_url: nil,
        commentary_url: nil,
        is_discussion_url: false
      )
    end

    private def sanitize_item_title(item : JSON::Any) : String?
      title = item["title"]?.try(&.as_s)
      Entry.sanitize_title(title)
    end

    private def resolve_item_url(item : JSON::Any, id : String) : String
      url_candidate = item["url"]?.try(&.as_s)
      return URLValidator.valid?(id) ? id : "#" unless url_candidate
      URLValidator.valid?(url_candidate) ? url_candidate : (URLValidator.valid?(id) ? id : "#")
    end

    private def extract_item_content(item : JSON::Any) : String
      content_html = item["content_html"]?.try(&.as_s)
      content_text = item["content_text"]?.try(&.as_s)
      content_html || content_text || ""
    end

    private def extract_item_author(item : JSON::Any) : String?
      authors_json = item["authors"]?.try(&.as_a) || item["author"]?.try(&.as_a)
      authors_json.try(&.first?).try(&.["name"]?.try(&.as_s))
    end

    private def extract_item_author_url(item : JSON::Any) : String?
      authors_json = item["authors"]?.try(&.as_a) || item["author"]?.try(&.as_a)
      authors_json.try(&.first?).try(&.["url"]?.try(&.as_s))
    end

    private def parse_item_date(item : JSON::Any) : Time?
      published = item["date_published"]?.try(&.as_s)
      modified = item["date_modified"]?.try(&.as_s)
      TimeParser.normalize(TimeParser.parse(published || modified))
    end

    private def extract_item_tags(item : JSON::Any) : Array(String)
      item["tags"]?.try(&.as_a).try(&.map(&.as_s)) || [] of String
    end

    private def parse_attachments(item : JSON::Any) : Array(Attachment)
      attachments_json = item["attachments"]?.try(&.as_a) || return [] of Attachment
      attachments_json.compact_map { |att| extract_attachment(att) }
    end

    private def extract_attachment(att_json : JSON::Any) : Attachment?
      url = att_json["url"]?.try(&.as_s)
      mime_type = att_json["mime_type"]?.try(&.as_s)
      return unless url && mime_type

      Attachment.new(
        url: url,
        mime_type: mime_type,
        title: att_json["title"]?.try(&.as_s),
        size_in_bytes: att_json["size_in_bytes"]?.try(&.as_i64),
        duration_in_seconds: att_json["duration_in_seconds"]?.try(&.as_i)
      )
    end
  end
end
