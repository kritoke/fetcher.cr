require "json"
require "./entry"
require "./result"
require "./time_parser"

module Fetcher
  # JSON streaming parser using JSON::PullParser with lazy iterator pattern
  class JSONStreamingParser
    def initialize(@limit : Int32 = 100)
      @entries_parsed = 0
    end

    # Parse JSON feed and return lazy iterator
    def parse(io : IO) : JSONStreamingIterator
      JSONStreamingIterator.new(io, @limit)
    end

    # Parse JSON feed and return array (for compatibility)
    def parse_entries(io : IO, limit : Int32? = nil) : Array(Entry)
      actual_limit = limit || @limit
      parse(io).to_a(actual_limit)
    end
  end

  # Lazy iterator for JSON streaming parser
  class JSONStreamingIterator < EntryIterator
    def initialize(@io : IO, @limit : Int32)
      super()
      @pull = JSON::PullParser.new(@io)
      @entries_parsed = 0
      @is_reddit = false
      @is_json_feed = false
    end

    protected def next_entry : Entry?
      return if @entries_parsed >= @limit

      # Determine feed type on first call
      unless @is_reddit || @is_json_feed
        determine_feed_type
      end

      if @is_reddit
        next_reddit_entry
      elsif @is_json_feed
        next_json_feed_entry
      end
    end

    private def determine_feed_type
      # Peek at JSON structure to determine type
      begin
        @pull.read_object do |key|
          if key == "data"
            # Likely Reddit
            @pull.read_object do |data_key|
              if data_key == "children"
                @is_reddit = true
                break
              else
                @pull.skip
              end
            end
          elsif key == "version" && @pull.read_string.includes?("jsonfeed")
            # JSON Feed
            @is_json_feed = true
            break
          else
            @pull.skip
          end
        end
      rescue
        # If we can't determine type, leave both as false
      end

      # Reset pull parser to beginning
      @pull = JSON::PullParser.new(@io)
    end

    private def next_reddit_entry : Entry?
      # We're already positioned in the children array
      # The first call will parse the first post
      @pull.read_object do |key|
        if key == "data"
          return parse_reddit_post_data_and_create
        else
          @pull.skip
        end
      end
      nil
    end

    private def parse_reddit_post_data_and_create : Entry?
      post_data = parse_reddit_post_data
      return unless post_data

      title = extract_string(post_data, :title, "Untitled")
      post_url = extract_string(post_data, :url, "")
      permalink = extract_string(post_data, :permalink, "")
      created_utc = extract_float(post_data, :created_utc, 0.0)
      is_self = extract_bool(post_data, :is_self, false)

      link = resolve_reddit_link(post_url, permalink, is_self)
      pub_date = created_utc > 0 ? Time.unix(created_utc.to_i64) : nil

      Entry.create(
        title: title,
        url: link,
        source_type: SourceType::Reddit,
        published_at: pub_date
      )
    rescue
      nil
    end

    private def extract_string(data : Hash(Symbol, String | Float64 | Bool), key : Symbol, default : String) : String
      value = data[key]?
      case value
      when String then value
      else             default
      end
    end

    private def extract_float(data : Hash(Symbol, String | Float64 | Bool), key : Symbol, default : Float64) : Float64
      value = data[key]?
      case value
      when Float64 then value
      when Int     then value.to_f64
      else              default
      end
    end

    private def extract_bool(data : Hash(Symbol, String | Float64 | Bool), key : Symbol, default : Bool) : Bool
      value = data[key]?
      case value
      when Bool then value
      else           default
      end
    end

    private def next_json_feed_entry : Entry?
      @pull.read_object do |key|
        if key == "items"
          @pull.read_array do
            # We're now in the items array
            return parse_json_feed_item
          end
        else
          @pull.skip
        end
      end

      nil
    end

    private def parse_reddit_post : Entry?
      # Parse Reddit post from current pull parser position
      # Expected format: {"data": {...post data...}}

      post_data = nil

      @pull.read_object do |key|
        if key == "data"
          post_data = parse_reddit_post_data
          break # Only need the first post
        else
          @pull.skip
        end
      end

      return unless post_data

      # Extract post fields
      title = post_data[:title] || "Untitled"
      post_url = post_data[:url] || ""
      permalink = post_data[:permalink] || ""
      created_utc = post_data[:created_utc] || 0.0
      is_self = post_data[:is_self] || false

      # Resolve link
      link = resolve_reddit_link(post_url, permalink, is_self)

      # Create published date
      pub_date = created_utc > 0 ? Time.unix(created_utc.to_i64) : nil

      Entry.create(
        title: title,
        url: link,
        source_type: SourceType::Reddit,
        published_at: pub_date
      )
    rescue
      # Skip malformed posts
      nil
    end

    private def parse_reddit_post_data : Hash(Symbol, String | Float64 | Bool)?
      data = {} of Symbol => String | Float64 | Bool

      @pull.read_object do |key|
        case key
        when "title"
          data[:title] = @pull.read_string
        when "url"
          data[:url] = @pull.read_string
        when "permalink"
          data[:permalink] = @pull.read_string
        when "created_utc"
          data[:created_utc] = @pull.read_float
        when "is_self"
          data[:is_self] = @pull.read_bool
        else
          @pull.skip
        end
      end

      data.empty? ? nil : data
    rescue
      nil
    end

    private def resolve_reddit_link(post_url : String, permalink : String, is_self : Bool) : String
      is_self || post_url.empty? ? "https://www.reddit.com#{permalink}" : post_url
    end

    private def parse_json_feed_item : Entry?
      item_data = parse_json_feed_item_data
      return unless item_data

      # Extract item fields with proper type handling
      title = extract_string_value(item_data, :title, "Untitled")
      url = extract_string_value(item_data, :url, extract_string_value(item_data, :id, "#"))
      content_html = extract_string_value(item_data, :content_html, nil)
      content_text = extract_string_value(item_data, :content_text, nil)
      date_published = extract_string_value(item_data, :date_published, nil)
      tags = extract_array_value(item_data, :tags)
      authors_data = extract_authors_value(item_data, :authors)

      # Create content
      content = content_html.presence || content_text.presence || ""

      # Parse published date
      pub_date = nil
      if date_published && !date_published.empty?
        pub_date = TimeParser.parse(date_published)
      end

      # Parse authors
      author = nil
      author_url = nil
      if authors_data.size > 0
        first_author = authors_data[0]
        author = first_author[:name]?
        author_url = first_author[:url]?
      end

      Entry.create(
        title: title,
        url: url,
        source_type: SourceType::JSONFeed,
        content: content,
        published_at: pub_date,
        author: author,
        author_url: author_url,
        categories: tags
      )
    rescue
      # Skip malformed items
      nil
    end

    private def extract_string_value(data : Hash, key : Symbol, default : String?) : String?
      value = data[key]?
      case value
      when String then value.empty? ? default : value
      else             default
      end
    end

    private def extract_array_value(data : Hash, key : Symbol) : Array(String)
      value = data[key]?
      case value
      when Array(String) then value
      else                    [] of String
      end
    end

    private def extract_authors_value(data : Hash, key : Symbol) : Array(Hash(Symbol, String))
      value = data[key]?
      case value
      when Array(Hash(Symbol, String)) then value
      else                                  [] of Hash(Symbol, String)
      end
    end

    private def parse_json_feed_item_data : Hash(Symbol, String | Array(String) | Array(Hash(Symbol, String)))?
      data = {} of Symbol => String | Array(String) | Array(Hash(Symbol, String))

      @pull.read_object do |key|
        case key
        when "id"
          data[:id] = @pull.read_string
        when "url"
          data[:url] = @pull.read_string
        when "title"
          data[:title] = @pull.read_string
        when "content_html"
          data[:content_html] = @pull.read_string
        when "content_text"
          data[:content_text] = @pull.read_string
        when "date_published"
          data[:date_published] = @pull.read_string
        when "tags"
          data[:tags] = parse_string_array
        when "authors"
          data[:authors] = parse_authors_array
        else
          @pull.skip
        end
      end

      data.empty? ? nil : data
    rescue
      nil
    end

    private def parse_string_array : Array(String)
      tags = [] of String
      @pull.read_array do
        tags << @pull.read_string
      end
      tags
    rescue
      [] of String
    end

    private def parse_authors_array : Array(Hash(Symbol, String))
      authors = [] of Hash(Symbol, String)
      @pull.read_array do
        name = nil
        url = nil
        @pull.read_object do |key|
          case key
          when "name"
            name = @pull.read_string
          when "url", "uri"
            url = @pull.read_string
          else
            @pull.skip
          end
        end
        if name || url
          author = {} of Symbol => String
          author[:name] = name if name
          author[:url] = url if url
          authors << author
        end
      end
      authors
    rescue
      [] of Hash(Symbol, String)
    end
  end
end
