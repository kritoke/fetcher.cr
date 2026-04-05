require "json"
require "./entry"
require "./link_resolver"

module Fetcher
  private record RedditPostData,
    title : String,
    url : String,
    permalink : String,
    created_utc : Float64,
    is_self : Bool

  class RedditJSONParser
    def initialize(@limit : Int32)
      @entries_parsed = 0
    end

    def next_entry(pull : JSON::PullParser) : Entry?
      return if @entries_parsed >= @limit

      pull.read_object do |key|
        if key == "data"
          post_data = parse_post_data(pull)
          return unless post_data
          @entries_parsed += 1
          return build_entry(post_data)
        else
          pull.skip
        end
      end
      nil
    end

    private def parse_post_data(pull : JSON::PullParser) : RedditPostData?
      title = "Untitled"
      url = ""
      permalink = ""
      created_utc = 0.0
      is_self = false

      pull.read_object do |key|
        case key
        when "title"       then title = pull.read_string
        when "url"         then url = pull.read_string
        when "permalink"   then permalink = pull.read_string
        when "created_utc" then created_utc = pull.read_float
        when "is_self"     then is_self = pull.read_bool
        else                    pull.skip
        end
      end

      RedditPostData.new(title, url, permalink, created_utc, is_self)
    rescue ex
      ::Log.for("fetcher.streaming").debug { "Failed to parse Reddit post data: #{ex.class} - #{ex.message}" }
      nil
    end

    private def build_entry(post : RedditPostData) : Entry
      link = if post.is_self || post.url.empty?
               "https://www.reddit.com#{post.permalink}"
             else
               post.url
             end
      pub_date = post.created_utc > 0 ? Time.unix(post.created_utc.to_i64) : nil
      link_data = LinkResolver.resolve_from_url(link)

      Entry.create(
        title: post.title,
        url: link,
        source_type: SourceType::Reddit,
        published_at: pub_date,
        comment_url: link_data.comment_url,
        commentary_url: link_data.commentary_url,
        is_discussion_url: link_data.is_discussion_url
      )
    end
  end
end
