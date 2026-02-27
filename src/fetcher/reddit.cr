require "json"
require "./entry"
require "./result"
require "./retry"
require "./http_client"

module Fetcher
  module Reddit
    USER_AGENT      = "QuickHeadlines/0.3 (Reddit Feed Fetcher)"
    REDDIT_API_BASE = "https://www.reddit.com"

    class RedditFetchError < Exception
    end

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100) : Result
      subreddit = extract_subreddit(url)
      return Fetcher.error_result("Not a Reddit subreddit URL") unless subreddit

      sort = extract_sort(url)
      actual_limit = Math.min(limit, 25)

      Fetcher.with_retry(
        is_retriable: ->(ex : Exception) {
          ex.is_a?(RetriableError) || ex.is_a?(RedditFetchError)
        }
      ) do
        fetch_reddit(subreddit, sort, actual_limit)
      end
    end

    private def self.fetch_reddit(subreddit : String, sort : String, limit : Int32) : Result
      url = "#{REDDIT_API_BASE}/r/#{subreddit}/#{sort}.json?limit=#{limit}&raw_json=1"
      headers = ::HTTP::Headers{
        "User-Agent" => USER_AGENT,
        "Accept"     => "application/json",
      }

      response = HTTPClient.fetch(url, headers)

      case response.status_code
      when 200
        items = parse_reddit_response(response.body, limit)
        site_link = "https://www.reddit.com/r/#{subreddit}"
        favicon = "https://www.reddit.com/favicon.ico"

        Result.new(
          entries: items,
          etag: nil,
          last_modified: nil,
          site_link: site_link,
          favicon: favicon,
          error_message: nil
        )
      when 404
        raise RedditFetchError.new("Subreddit '#{subreddit}' not found")
      when 429
        raise RetriableError.new("Rate limited by Reddit API")
      when 503
        raise RetriableError.new("Reddit service unavailable")
      else
        raise RedditFetchError.new("HTTP error #{response.status_code}")
      end
    end

    private def self.extract_subreddit(url : String) : String?
      match = url.match(%r{reddit\.com/r/([^/]+)}i)
      match ? match[1] : nil
    end

    private def self.extract_sort(url : String) : String
      return "top" if url.includes?("/top.")
      return "new" if url.includes?("/new.")
      return "rising" if url.includes?("/rising.")
      "hot"
    end

    private def self.parse_reddit_response(body : String, limit : Int32) : Array(Entry)
      parsed = JSON.parse(body)
      children = extract_children(parsed)
      return [] of Entry if children.nil?

      children.first(limit).compact_map { |child| parse_reddit_post(child) }
    end

    private def self.extract_children(parsed : JSON::Any) : Array(JSON::Any)?
      data = parsed.as_a? ? parsed[0]["data"]? : parsed["data"]?
      children = data.try(&.["children"]?)
      children.as_a? if children
    end

    private def self.parse_reddit_post(child : JSON::Any) : Entry?
      post = child["data"]? || return

      title = post["title"]?.try(&.as_s) || "Untitled"
      post_url = post["url"]?.try(&.as_s) || ""
      permalink = post["permalink"]?.try(&.as_s) || ""
      created_utc = post["created_utc"]?.try(&.as_f) || 0.0
      is_self = post["is_self"]?.try(&.as_bool) || false

      link = resolve_reddit_link(post_url, permalink, is_self)
      pub_date = created_utc > 0 ? Time.unix(created_utc.to_i64) : nil

      Entry.new(title, link, "", nil, pub_date, "reddit", nil)
    end

    private def self.resolve_reddit_link(post_url : String, permalink : String, is_self : Bool) : String
      is_self || post_url.empty? ? "https://www.reddit.com#{permalink}" : post_url
    end
  end
end
