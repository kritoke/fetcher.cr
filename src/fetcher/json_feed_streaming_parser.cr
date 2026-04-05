require "json"
require "./entry"
require "./time_parser"
require "./link_resolver"

module Fetcher
  private record StreamingAuthorInfo,
    name : String?,
    url : String?

  private record StreamingJSONFeedItemData,
    id : String?,
    url : String?,
    title : String?,
    content_html : String?,
    content_text : String?,
    date_published : String?,
    tags : Array(String),
    authors : Array(StreamingAuthorInfo)

  class JSONFeedStreamingParser
    def initialize(@limit : Int32)
      @entries_parsed = 0
      @in_items_array = false
    end

    def next_entry(pull : JSON::PullParser) : Entry?
      return if @entries_parsed >= @limit

      unless @in_items_array
        pull.read_object do |key|
          if key == "items"
            @in_items_array = true
            pull.read_array do
              return parse_and_build(pull)
            end
          else
            pull.skip
          end
        end
        return
      end

      pull.read_array do
        return parse_and_build(pull)
      end
      nil
    end

    private def parse_and_build(pull : JSON::PullParser) : Entry?
      item_data = parse_item_data(pull)
      return unless item_data
      @entries_parsed += 1
      build_entry(item_data)
    end

    private def parse_item_data(pull : JSON::PullParser) : StreamingJSONFeedItemData?
      id = nil
      url = nil
      title = nil
      content_html = nil
      content_text = nil
      date_published = nil
      tags = [] of String
      authors = [] of StreamingAuthorInfo

      pull.read_object do |key|
        case key
        when "id"             then id = pull.read_string
        when "url"            then url = pull.read_string
        when "title"          then title = pull.read_string
        when "content_html"   then content_html = pull.read_string
        when "content_text"   then content_text = pull.read_string
        when "date_published" then date_published = pull.read_string
        when "tags"           then tags = parse_string_array(pull)
        when "authors"        then authors = parse_authors_array(pull)
        else                       pull.skip
        end
      end

      StreamingJSONFeedItemData.new(id, url, title, content_html, content_text, date_published, tags, authors)
    rescue ex
      ::Log.for("fetcher.streaming").debug { "Failed to parse JSON Feed item data: #{ex.class} - #{ex.message}" }
      nil
    end

    private def build_entry(item : StreamingJSONFeedItemData) : Entry
      title = item.title.presence || "Untitled"
      url = item.url.presence || item.id.presence || "#"
      content = item.content_html.presence || item.content_text.presence || ""

      pub_date = nil
      if (dp = item.date_published) && !dp.empty?
        pub_date = TimeParser.parse(dp)
      end

      author = nil
      author_url = nil
      if first = item.authors.first?
        author = first.name
        author_url = first.url
      end

      link_data = LinkResolver.resolve_from_url(url)

      Entry.create(
        title: title,
        url: url,
        source_type: SourceType::JSONFeed,
        content: content,
        published_at: pub_date,
        author: author,
        author_url: author_url,
        categories: item.tags,
        comment_url: link_data.comment_url,
        commentary_url: link_data.commentary_url,
        is_discussion_url: link_data.is_discussion_url
      )
    end

    private def parse_string_array(pull : JSON::PullParser) : Array(String)
      tags = [] of String
      pull.read_array do
        tags << pull.read_string
      end
      tags
    rescue ex
      ::Log.for("fetcher.streaming").debug { "Failed to parse string array: #{ex.class} - #{ex.message}" }
      [] of String
    end

    private def parse_authors_array(pull : JSON::PullParser) : Array(StreamingAuthorInfo)
      authors = [] of StreamingAuthorInfo
      pull.read_array do
        name = nil
        url = nil
        pull.read_object do |key|
          case key
          when "name"       then name = pull.read_string
          when "url", "uri" then url = pull.read_string
          else                   pull.skip
          end
        end
        authors << StreamingAuthorInfo.new(name, url) if name || url
      end
      authors
    rescue ex
      ::Log.for("fetcher.streaming").debug { "Failed to parse authors array: #{ex.class} - #{ex.message}" }
      [] of StreamingAuthorInfo
    end
  end
end
