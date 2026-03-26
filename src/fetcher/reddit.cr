require "json"
require "./entry"
require "./result"
require "./retry"
require "./crest_http_client"
require "./rss"
require "./exceptions"
require "./json_streaming_parser"
require "./link_resolver"

module Fetcher
  module Reddit
    USER_AGENT      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    REDDIT_API_BASE = "https://www.reddit.com"

    class RedditFetchError < Exception
    end

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      subreddit = extract_subreddit(url)
      return Fetcher.error_result(ErrorKind::InvalidURL, "Not a Reddit subreddit URL") unless subreddit

      sort = extract_sort(url)
      actual_limit = Math.min(limit, 25)

      cache_key = Cache.generate_key(subreddit, sort, actual_limit)

      if config.cache_enabled
        if cached = Cache.get(cache_key)
          return cached
        end
      end

      result = Fetcher.with_retry(config) do
        begin
          fetch_reddit(subreddit, sort, actual_limit, headers, config)
        rescue FetchError
          fetch_reddit_rss(subreddit, sort, actual_limit, headers, config)
        end
      end

      if config.cache_enabled && result.success?
        ttl = Cache.ttl_for_sort(sort)
        Cache.set(cache_key, result, ttl)
      end

      result
    end

    private def self.fetch_reddit_rss(subreddit : String, sort : String, limit : Int32, headers : ::HTTP::Headers, config : RequestConfig) : Result
      rss_url = "#{REDDIT_API_BASE}/r/#{subreddit}/#{sort}.rss"
      rss_headers = headers.dup
      rss_headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
      RSS.pull(rss_url, rss_headers, limit, config)
    end

    private def self.fetch_reddit(subreddit : String, sort : String, limit : Int32, headers : ::HTTP::Headers, config : RequestConfig) : Result
      url = "#{REDDIT_API_BASE}/r/#{subreddit}/#{sort}.json?limit=#{limit}&raw_json=1"
      reddit_headers = ::HTTP::Headers{
        "User-Agent" => USER_AGENT,
        "Accept"     => "application/json",
      }
      final_headers = reddit_headers.dup
      final_headers.merge!(headers)

      http_client = Fetcher::CrestHttpClient.new(config)
      response = http_client.get(url, final_headers)

      case response.status_code
      when 200..299
        # Use streaming parser if configured
        if config.use_streaming_parser
          begin
            io = IO::Memory.new(response.body)
            parser = Fetcher::JSONStreamingParser.new(limit)
            items = parser.parse_entries(io, limit)

            site_link = "https://www.reddit.com/r/#{subreddit}"
            favicon = "https://www.reddit.com/favicon.ico"

            return Result.success(
              entries: items,
              site_link: site_link,
              favicon: favicon
            )
          rescue ex : Fetcher::StreamingErrorHandling::MemoryLimitExceeded
            # Don't fallback for memory issues
            puts "Reddit streaming parser memory limit exceeded, cannot fallback" if config.debug_streaming
            error = Error.invalid_format(ex.message || "Feed too large", url)
            return Result.error(error)
          rescue ex
            puts "Reddit streaming parser failed: #{ex.class} - #{ex.message}, falling back to DOM parser" if config.debug_streaming
          end
        end

        # Fallback to DOM parser
        items = parse_reddit_response(response.body, limit)
        site_link = "https://www.reddit.com/r/#{subreddit}"
        favicon = "https://www.reddit.com/favicon.ico"

        Result.success(
          entries: items,
          site_link: site_link,
          favicon: favicon
        )
      when 404
        error = Error.invalid_url("Subreddit '#{subreddit}' not found", url)
        raise InvalidURLError.new(error.message, error)
      when 429
        error = Error.rate_limited("Rate limited by Reddit API", url)
        raise RateLimitError.new(error.message, error)
      when 500..599
        error = Error.server_error(response.status_code, "Reddit server error: #{response.status_code}", url)
        raise HTTPServerError.new(error.message, response.status_code, error)
      else
        error = Error.http(response.status_code, "HTTP error #{response.status_code}", url)
        raise HTTPError.new(error.message, response.status_code, error)
      end
    rescue ex : IO::TimeoutError
      error = Error.timeout("Timeout: #{ex.message}", url)
      raise TimeoutError.new(error.message, error)
    rescue ex : CrestHttpClient::DNSError
      error = Error.dns("DNS error: #{ex.message}", url)
      raise DNSError.new(error.message, error)
    rescue ex : JSON::ParseException
      error = Error.invalid_format("JSON parsing error: #{ex.message}", url)
      raise InvalidFormatError.new(error.message, error)
    rescue ex : FetchError
      # Re-raise typed exceptions
      raise ex
    rescue ex
      if Fetcher.transient_error?(ex)
        error = Error.unknown(ex.message || "Unknown error", url)
        raise UnknownError.new(error.message, error)
      end
      error = Error.unknown("#{ex.class}: #{ex.message}", url)
      ::Log.for("fetcher.reddit").debug { "Reddit fetch error for #{url}: #{ex.class} - #{ex.message}" } if ENV["FETCHER_DEBUG"]?
      Fetcher.error_result(error)
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

    def self.parse_reddit_response(body : String, limit : Int32) : Array(Entry)
      parsed = JSON.parse(body)
      children = extract_children(parsed)
      return [] of Entry if children.nil?

      children.first(limit).compact_map { |child| parse_reddit_post(child) }
    rescue JSON::ParseException
      [] of Entry
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

      discussion_url = "https://www.reddit.com#{permalink}"
      external_url = is_self || post_url.empty? ? nil : post_url
      pub_date = created_utc > 0 ? Time.unix(created_utc.to_i64) : nil

      Entry.create(
        title: title,
        url: discussion_url,
        source_type: SourceType::Reddit,
        published_at: pub_date,
        is_discussion_url: true,
        comment_url: external_url
      )
    end
  end
end
