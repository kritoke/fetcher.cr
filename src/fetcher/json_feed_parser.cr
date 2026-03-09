require "json"
require "./entry"
require "./result"
require "./entry_parser"
require "./time_parser"
require "./author"
require "./attachment"

module Fetcher
  # JSON Feed parser implementation
  class JSONFeedParser < EntryParser
    def parse_entries(data : String, limit : Int32) : Array(Entry)
      parsed = parse_json(data)

      version = parsed["version"]?.try(&.as_s)
      raise InvalidFormatError.new("Invalid JSON Feed: missing version") unless version
      raise InvalidFormatError.new("Unsupported JSON Feed version") unless version.includes?("https://jsonfeed.org/version/")

      items = parsed["items"]?.try(&.as_a) || [] of JSON::Any
      items.first(limit).compact_map { |item| parse_item(item) }
    end

    def parse_feed_metadata(data : String) : NamedTuple(
      site_link: String?,
      favicon: String?,
      feed_title: String?,
      feed_description: String?,
      feed_language: String?,
      feed_authors: Array(Author))
      parsed = parse_json(data)

      home_url = parsed["home_page_url"]?.try(&.as_s)
      favicon = parsed["favicon"]?.try(&.as_s)
      icon = parsed["icon"]?.try(&.as_s)
      feed_title = parsed["title"]?.try(&.as_s)
      description = parsed["description"]?.try(&.as_s)
      feed_language = parsed["language"]?.try(&.as_s)

      feed_authors = parse_authors(parsed)

      {
        site_link:        home_url,
        favicon:          favicon || icon,
        feed_title:       feed_title,
        feed_description: description,
        feed_language:    feed_language,
        feed_authors:     feed_authors,
      }
    end

    private def parse_json(data : String) : JSON::Any
      JSON.parse(data)
    rescue ex : JSON::ParseException
      raise InvalidFormatError.new("JSON parsing error: #{ex.message}")
    end

    private def parse_authors(parsed : JSON::Any) : Array(Author)
      authors_json = parsed["authors"]?.try(&.as_a) || parsed["author"]?.try(&.as_a)
      return [] of Author unless authors_json

      authors_json.compact_map do |author_json|
        name = author_json["name"]?.try(&.as_s)
        next unless name
        Author.new(
          name: name,
          url: author_json["url"]?.try(&.as_s),
          avatar: author_json["avatar"]?.try(&.as_s)
        )
      end
    end

    private def parse_item(item : JSON::Any) : Entry?
      id = item["id"]?.try(&.to_s)
      return if id.nil? || id.empty?

      url = item["url"]?.try(&.as_s) || id
      title = item["title"]?.try(&.as_s)
      title = Entry.sanitize_title(title)

      content_html = item["content_html"]?.try(&.as_s)
      content_text = item["content_text"]?.try(&.as_s)
      content = content_html || content_text || ""

      published = item["date_published"]?.try(&.as_s)
      modified = item["date_modified"]?.try(&.as_s)
      pub_date = TimeParser.parse_iso8601(published || modified)

      tags = item["tags"]?.try(&.as_a).try(&.map(&.as_s)) || [] of String

      attachments = parse_attachments(item)

      authors_json = item["authors"]?.try(&.as_a) || item["author"]?.try(&.as_a)
      author = authors_json.try(&.first?).try(&.["name"]?.try(&.as_s))
      author_url = authors_json.try(&.first?).try(&.["url"]?.try(&.as_s))

      Entry.create(
        title: title,
        url: url,
        source_type: SourceType::JSONFeed,
        content: content,
        author: author,
        author_url: author_url,
        published_at: pub_date,
        categories: tags,
        attachments: attachments
      )
    end

    private def parse_attachments(item : JSON::Any) : Array(Attachment)
      attachments_json = item["attachments"]?.try(&.as_a)
      return [] of Attachment unless attachments_json

      attachments_json.compact_map do |att_json|
        url = att_json["url"]?.try(&.as_s)
        mime_type = att_json["mime_type"]?.try(&.as_s)
        next unless url && mime_type

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
end
