require "json"
require "./entry"
require "./result"
require "./retry"
require "./crest_http_client"
require "./rss"
require "./exceptions"
require "./json_streaming_parser"
require "./link_resolver"
require "./header_builder"

module Fetcher
  module Reddit
    USER_AGENT      = HeaderBuilder::DEFAULT_USER_AGENT
    REDDIT_API_BASE = "https://www.reddit.com"

    class RedditFetchError < Exception
      getter original_cause : Exception?

      def initialize(message : String, @original_cause : Exception? = nil)
        super(message)
      end
    end

    REDDIT_CACHE_TTL_NEW           = 30.seconds
    REDDIT_CACHE_TTL_RISING        = 30.seconds
    REDDIT_CACHE_TTL_HOT           = 2.minutes
    REDDIT_CACHE_TTL_TOP           = 10.minutes
    REDDIT_CACHE_TTL_CONTROVERSIAL = 10.minutes

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      subreddit = extract_subreddit(url)
      return Fetcher.error_result(ErrorKind::InvalidURL, "Not a Reddit subreddit URL") unless subreddit

      sort = extract_sort(url)
      actual_limit = Math.min(limit, 25)

      cache_key = generate_cache_key(subreddit, sort, actual_limit)

      if config.cache_config.enabled
        if cached = config.cache.get(cache_key)
          return cached
        end
      end

      result = fetch_with_reddit_fallback(subreddit, sort, actual_limit, headers, config)

      if config.cache_config.enabled && result.success?
        ttl = ttl_for_sort(sort)
        config.cache.set(cache_key, result, ttl)
      end

      result
    end

    private def self.fetch_reddit_rss(subreddit : String, sort : String, limit : Int32, headers : ::HTTP::Headers, config : RequestConfig) : Result
      rss_url = "#{REDDIT_API_BASE}/r/#{subreddit}/#{sort}.rss"
      rss_headers = headers.dup
      rss_headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
      RSS.pull(rss_url, rss_headers, limit, config)
    end

    private def self.fetch_with_reddit_fallback(subreddit : String, sort : String, limit : Int32, headers : ::HTTP::Headers, config : RequestConfig) : Result
      result = Fetcher.with_retry(config) do
        fetch_reddit(subreddit, sort, limit, headers, config)
      end

      return result if result.success?

      # Fall back to RSS for transient errors (excluding rate limiting)
      error = result.error
      if error && transient_error_kind?(error.kind) && error.kind != ErrorKind::RateLimited
        fetch_reddit_rss(subreddit, sort, limit, headers, config)
      else
        result
      end
    end

    private def self.fetch_reddit(subreddit : String, sort : String, limit : Int32, headers : ::HTTP::Headers, config : RequestConfig) : Result
      api_url = "#{REDDIT_API_BASE}/r/#{subreddit}/#{sort}.json?limit=#{limit}&raw_json=1"
      reddit_headers = ::HTTP::Headers{
        "User-Agent" => USER_AGENT,
        "Accept"     => "application/json",
      }
      final_headers = reddit_headers.dup
      final_headers.merge!(headers)

      http_client = Fetcher::CrestHttpClient.new(config)
      response = http_client.get(api_url, final_headers)

      case response.status_code
      when 200..299
        result = try_streaming_parse(response.body, subreddit, limit, config)
        return result if result

        build_reddit_result(parse_reddit_response(response.body, limit), subreddit)
      when 404
        error = Error.invalid_url("Subreddit '#{subreddit}' not found", api_url)
        raise InvalidURLError.new(error.message, error)
      when 429
        error = Error.rate_limited("Rate limited by Reddit API", api_url)
        raise RateLimitError.new(error.message, error)
      when 500..599
        error = Error.server_error(response.status_code, "Reddit server error: #{response.status_code}", api_url)
        raise HTTPServerError.new(error.message, response.status_code, error)
      else
        error = Error.http(response.status_code, "HTTP error #{response.status_code}", api_url)
        raise HTTPError.new(error.message, response.status_code, error)
      end
    rescue ex : IO::TimeoutError
      error = Error.timeout("Timeout: #{ex.message}", api_url)
      raise RedditFetchError.new(error.message, TimeoutError.new(error.message, error))
    rescue ex : CrestHttpClient::DNSError
      error = Error.dns("DNS error: #{ex.message}", api_url)
      raise RedditFetchError.new(error.message, DNSError.new(error.message, error))
    rescue ex : JSON::ParseException
      error = Error.invalid_format("JSON parsing error: #{ex.message}", api_url)
      raise RedditFetchError.new(error.message, InvalidFormatError.new(error.message, error))
    rescue ex : RedditFetchError
      raise ex
    rescue ex : FetchError
      raise RedditFetchError.new(ex.message || "Reddit API failed", ex)
    rescue ex
      raise RedditFetchError.new("#{ex.class}: #{ex.message}", ex)
    end

    private def self.try_streaming_parse(body : String, subreddit : String, limit : Int32, config : RequestConfig) : Result?
      return unless config.streaming.enabled

      io = IO::Memory.new(body)
      parser = Fetcher::JSONStreamingParser.new(limit)
      items = parser.parse_entries(io, limit)

      build_reddit_result(items, subreddit)
    rescue ex : Fetcher::MemoryLimitExceeded
      ::Log.for("fetcher.reddit").debug { "Streaming parser memory limit exceeded, cannot fallback" } if config.streaming.debug
      error = Error.invalid_format(ex.message || "Feed too large", "#{REDDIT_API_BASE}/r/#{subreddit}")
      Result.error(error)
    rescue ex
      ::Log.for("fetcher.reddit").debug { "Streaming parser failed: #{ex.class} - #{ex.message}, falling back to DOM parser" } if config.streaming.debug
      nil
    end

    private def self.build_reddit_result(entries : Array(Entry), subreddit : String) : Result
      Result.success(
        entries: entries,
        site_link: "https://www.reddit.com/r/#{subreddit}",
        favicon: "https://www.reddit.com/favicon.ico"
      )
    end

    private def self.extract_subreddit(url : String) : String?
      match = url.match(%r{reddit\.com/r/([^/]+)}i)
      match ? match[1] : nil
    end

    private def self.extract_sort(url : String) : String
      begin
        uri = URI.parse(url)
        path = uri.path || ""
        segments = path.split('/').reject(&.empty?)
        return "top" if segments.last? == "top"
        return "new" if segments.last? == "new"
        return "rising" if segments.last? == "rising"
      rescue
      end
      "hot"
    end

    def self.generate_cache_key(subreddit : String, sort : String, limit : Int32) : String
      "reddit:#{subreddit}:#{sort}:#{limit}"
    end

    def self.ttl_for_sort(sort : String) : Time::Span
      case sort
      when "new"           then REDDIT_CACHE_TTL_NEW
      when "rising"        then REDDIT_CACHE_TTL_RISING
      when "hot"           then REDDIT_CACHE_TTL_HOT
      when "top"           then REDDIT_CACHE_TTL_TOP
      when "controversial" then REDDIT_CACHE_TTL_CONTROVERSIAL
      else                      Cache::DEFAULT_TTL
      end
    end

    def self.clear_cache(subreddit : String) : Nil
      Cache.default.clear_by_prefix("reddit:#{subreddit}:")
    end

    private def self.transient_error_kind?(kind : ErrorKind?) : Bool
      return false unless kind
      case kind
      when .timeout?, .dns_error?, .server_error?, .rate_limited?
        true
      else
        false
      end
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
    rescue ex
      ::Log.for("fetcher.reddit").warn { "Unexpected JSON structure in Reddit response: #{ex.message}" }
      nil
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
        url: external_url || discussion_url,
        source_type: SourceType::Reddit,
        published_at: pub_date,
        is_discussion_url: false,
        comment_url: discussion_url
      )
    end
  end
end
