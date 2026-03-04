require "json"
require "./entry"
require "./result"
require "./retry"
require "./http_client"
require "./time_parser"
require "./author"
require "./attachment"

module Fetcher
  module JSONFeed
    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      Fetcher.with_retry do
        perform_fetch(url, headers, limit, config)
      end
    end

    private def self.perform_fetch(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      response = HTTPClient.fetch(url, headers, config)

      case response.status_code
      when 304
        Result.success(
          entries: [] of Entry,
          etag: response.headers["ETag"]?,
          last_modified: response.headers["Last-Modified"]?
        )
      when 200..299
        parse_feed(response.body, limit)
      when 500..599
        raise RetriableError.new("Server error: #{response.status_code}")
      else
        Fetcher.error_result("HTTP #{response.status_code}")
      end
    rescue ex : IO::TimeoutError
      raise RetriableError.new("Timeout: #{ex.message}")
    rescue ex : HTTPClient::DNSError
      raise RetriableError.new("DNS error: #{ex.message}")
    rescue ex
      if Fetcher.transient_error?(ex)
        raise RetriableError.new(ex.message || "Unknown error")
      end
      Fetcher.error_result("#{ex.class}: #{ex.message}")
    end

    private def self.parse_feed(body : String, limit : Int32) : Result
      parsed = JSON.parse(body)

      version = parsed["version"]?.try(&.as_s)
      return Fetcher.error_result("Invalid JSON Feed: missing version") unless version
      return Fetcher.error_result("Unsupported JSON Feed version") unless version.includes?("https://jsonfeed.org/version/")

      feed_title = parsed["title"]?.try(&.as_s)
      home_url = parsed["home_page_url"]?.try(&.as_s)
      description = parsed["description"]?.try(&.as_s)
      favicon = parsed["favicon"]?.try(&.as_s)
      icon = parsed["icon"]?.try(&.as_s)
      feed_language = parsed["language"]?.try(&.as_s)

      feed_authors = parse_authors(parsed)

      items = parsed["items"]?.try(&.as_a) || [] of JSON::Any
      entries = items.first(limit).compact_map { |item| parse_item(item) }

      Result.success(
        entries: entries,
        site_link: home_url,
        favicon: favicon || icon,
        feed_title: feed_title,
        feed_description: description,
        feed_language: feed_language,
        feed_authors: feed_authors
      )
    rescue ex : JSON::ParseException
      Fetcher.error_result("JSON parsing error: #{ex.message}")
    rescue ex
      Fetcher.error_result("Error: #{ex.class} - #{ex.message}")
    end

    private def self.parse_authors(parsed : JSON::Any) : Array(Author)
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

    private def self.parse_item(item : JSON::Any) : Entry?
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
        source_type: "jsonfeed",
        content: content,
        author: author,
        author_url: author_url,
        published_at: pub_date,
        categories: tags,
        attachments: attachments
      )
    end

    private def self.parse_attachments(item : JSON::Any) : Array(Attachment)
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
