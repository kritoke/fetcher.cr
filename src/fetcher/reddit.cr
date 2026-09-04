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
require "./config"
require "./reddit_oauth"
require "./url_validator"

module Fetcher
  module Reddit
    USER_AGENT          = "fetcher.cr/#{Fetcher::VERSION} (https://github.com/kritoke/fetcher.cr; 3081486+kritoke@users.noreply.github.com)"
    REDDIT_API_BASE     = "https://www.reddit.com"
    OLD_REDDIT_API_BASE = "https://old.reddit.com"

    # Diagnostics and response formatting constants
    MAX_BODY_SNIPPET  = 512

    class RedditFetchError < Exception
      getter original_cause : Exception?

      def initialize(message : String, @original_cause : Exception? = nil)
        super(message)
      end
    end

    # Data-driven TTLs for caching by sort and backend
    REDDIT_TTLS = {
      "new"           => 30.seconds,
      "rising"        => 30.seconds,
      "hot"           => 2.minutes,
      "top"           => 10.minutes,
      "controversial" => 10.minutes,
    }

    OLD_REDDIT_TTLS = {
      "new"           => 5.minutes,
      "rising"        => 5.minutes,
      "hot"           => 15.minutes,
      "top"           => 30.minutes,
      "controversial" => 30.minutes,
      "default"       => 15.minutes,
    }

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      subreddit = extract_sub(url)
      return Fetcher.error_result(ErrorKind::InvalidURL, "Not a Reddit subreddit URL") unless subreddit

      sort = extract_sort(url)
      actual_limit = Math.min(limit, Config::REDDIT_MAX_POSTS_PER_REQUEST)

      cache_key = generate_cache_key(subreddit, sort, actual_limit)

      if config.cache_config.enabled
        if cached = config.cache.get(cache_key)
          return cached
        end
      end

      result = fetch_fallback(subreddit, sort, actual_limit, headers, config)

      if config.cache_config.enabled && result[:result].success?
        ttl = result[:source] == :old_reddit ? old_ttl_for_sort(sort) : ttl_for_sort(sort)
        config.cache.set(cache_key, result[:result], ttl)
      end

      result[:result]
    end

    private def self.fetch_rss(subreddit : String, sort : String, limit : Int32, headers : ::HTTP::Headers, config : RequestConfig) : Result
      rss_url = "#{REDDIT_API_BASE}/r/#{subreddit}/#{sort}.rss"
      rss_headers = headers.dup
      rss_headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
      RSS.pull(rss_url, rss_headers, limit, config)
    end

    private def self.log_fetch_diagnostics(api_url : String, final_headers : ::HTTP::Headers) : Nil
      uri = URI.parse(api_url)
      host = uri.host
      addresses = if host && !host.empty?
                    begin
                      Socket::Addrinfo.resolve(host, URLValidator::DNS_RESOLVE_PORT.to_s, type: Socket::Type::STREAM, protocol: Socket::Protocol::TCP)
                        .map(&.ip_address.to_s)
                    rescue ex
                      ["resolve_failed: #{ex.message}"]
                    end
                  else
                    ["no_host"]
                  end
      ::Log.for("fetcher.reddit").debug { "Fetching Reddit API #{api_url} from resolved addresses: #{addresses.join(", ")}" }
      ::Log.for("fetcher.reddit").debug { "Request headers: User-Agent=#{final_headers["User-Agent"]?}, Accept=#{final_headers["Accept"]?}" }
    rescue ex
      ::Log.for("fetcher.reddit").debug { "Failed to resolve/log diagnostics for #{api_url}: #{ex.message}" }
    end

    private def self.fetch_fallback(subreddit : String, sort : String, limit : Int32, headers : ::HTTP::Headers, config : RequestConfig) : NamedTuple(result: Result, source: Symbol)
      result = Fetcher.with_retry(config) do
        fetch_reddit_api(subreddit, sort, limit, headers, config)
      end

      return {result: result, source: :api} if result.success?

      error = result.error
      should_try_rss = error && (error.status_code == 403 || transient_error?(error.kind))
      if should_try_rss && (err = error)
        ::Log.for("fetcher.reddit").warn { "Reddit API returned #{err.status_code || "transient error"} for /r/#{subreddit} - trying RSS fallback" }
        rss_result = fetch_rss(subreddit, sort, limit, headers, config)
        return {result: rss_result, source: :rss} if rss_result.success?
      end

      old_result = Fetcher.with_retry(config.with_retry_max_retries(2)) do
        fetch_reddit_api(subreddit, sort, limit, headers, config, OLD_REDDIT_API_BASE)
      end
      {result: old_result, source: old_result.success? ? :old_reddit : :failed}
    end

    private def self.fetch_reddit_api(subreddit : String, sort : String, limit : Int32, headers : ::HTTP::Headers, config : RequestConfig, api_base : String = REDDIT_API_BASE) : Result
      api_url = "#{api_base}/r/#{subreddit}/#{sort}.json?limit=#{limit}&raw_json=1"
      reddit_headers = ::HTTP::Headers{
        "User-Agent" => USER_AGENT,
        "Accept"     => "application/json",
      }
      final_headers = reddit_headers.dup
      final_headers.merge!(headers)

      if token = RedditOAuth.get_token(config)
        final_headers["Authorization"] = "Bearer #{token}"
      end

      http_client = Fetcher::CrestHttpClient.new(config)
      log_fetch_diagnostics(api_url, final_headers)

      response = http_client.get(api_url, final_headers)
      handle_reddit_response(response, api_url, subreddit, limit, config)
    rescue ex : RedditFetchError
      raise ex
    rescue ex : FetchError
      raise RedditFetchError.new(ex.message || "Reddit API failed", ex)
    rescue ex
      raise reddit_error(ex, api_url || "unknown")
    end

    private def self.reddit_error(ex : Exception, api_url : String) : RedditFetchError
      case ex
      when IO::TimeoutError
        wrapped = Error.timeout("Timeout: #{ex.message}", api_url)
        RedditFetchError.new(wrapped.message, TimeoutError.new(wrapped.message, wrapped))
      when CrestHttpClient::DNSError
        wrapped = Error.dns("DNS error: #{ex.message}", api_url)
        RedditFetchError.new(wrapped.message, DNSError.new(wrapped.message, wrapped))
      when JSON::ParseException
        wrapped = Error.invalid_format("JSON parsing error: #{ex.message}", api_url)
        RedditFetchError.new(wrapped.message, InvalidFormatError.new(wrapped.message, wrapped))
      else
        RedditFetchError.new("#{ex.class}: #{ex.message}", ex)
      end
    end

    private def self.try_stream(body : String, subreddit : String, limit : Int32, config : RequestConfig) : Result?
      return unless config.streaming.enabled

      io = IO::Memory.new(body)
      parser = Fetcher::JSONStreamingParser.new(limit)
      items = parser.parse_entries(io, limit)

      build_result(items, subreddit)
    rescue ex : Fetcher::MemoryLimitExceeded
      ::Log.for("fetcher.reddit").debug { "Streaming parser memory limit exceeded, cannot fallback" } if config.streaming.debug
      error = Error.invalid_format(ex.message || "Feed too large", "#{REDDIT_API_BASE}/r/#{subreddit}")
      Result.error(error)
    rescue ex
      ::Log.for("fetcher.reddit").debug { "Streaming parser failed: #{ex.class} - #{ex.message}, falling back to DOM parser" } if config.streaming.debug
      nil
    end

    private def self.handle_reddit_response(response, api_url : String, subreddit : String, limit : Int32, config : RequestConfig) : Result
      case response.status_code
      when 200..299
        result = try_stream(response.body, subreddit, limit, config)
        return result if result

        build_result(parse_reddit_response(response.body, limit), subreddit)
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
        detail = build_response_detail(response)
        ::Log.for("fetcher.reddit").warn { "Reddit API returned non-OK status: #{detail} for #{api_url}" }

        error = Error.http(response.status_code, "HTTP error #{response.status_code}: #{detail}", api_url)
        raise HTTPError.new(error.message, response.status_code, error)
      end
    end

    private def self.build_response_detail(response) : String
      server = response.headers["server"]? || response.headers["Server"]?
      via = response.headers["via"]? || response.headers["Via"]?
      rate_remaining = response.headers["x-ratelimit-remaining"]? || response.headers["X-Ratelimit-Remaining"]?
      content_type = response.headers["content-type"]? || response.headers["Content-Type"]?

      body_snippet = begin
        if response.body && response.body.is_a?(String)
          response.body[0, MAX_BODY_SNIPPET].gsub(/\s+/, " ").strip
        end
      rescue
        nil
      end

      parts = ["status=#{response.status_code}"]
      parts << "server=#{server}" if server
      parts << "via=#{via}" if via
      parts << "rate_remaining=#{rate_remaining}" if rate_remaining
      parts << "content_type=#{content_type}" if content_type
      parts << "body=#{body_snippet}" if body_snippet
      parts.join("; ")
    end

    private def self.build_result(entries : Array(Entry), subreddit : String) : Result
      Result.builder
        .entries(entries)
        .site_link("https://www.reddit.com/r/#{subreddit}")
        .favicon("https://www.reddit.com/favicon.ico")
        .build
    end

    VALID_SUBREDDIT = /^[A-Za-z0-9_+%]+$/
    VALID_SORTS     = {"hot", "new", "rising", "top", "controversial"}

    private def self.extract_sub(url : String) : String?
      match = url.match(%r{reddit\.com/r/([^/]+)}i)
      return unless match
      sub = match[1]
      sub if sub.matches?(VALID_SUBREDDIT)
    end

    private def self.extract_sort(url : String) : String
      match = url.match(%r{reddit\.com/r/[^/]+/([^/]+)}i)
      sort = match ? match[1] : "hot"
      VALID_SORTS.includes?(sort.downcase) ? sort.downcase : "hot"
    end

    def self.generate_cache_key(subreddit : String, sort : String, limit : Int32) : String
      "reddit:#{subreddit}:#{sort}:#{limit}"
    end

    def self.ttl_for_sort(sort : String) : Time::Span
      REDDIT_TTLS[sort]? || Cache::DEFAULT_TTL
    end

    def self.old_ttl_for_sort(sort : String) : Time::Span
      OLD_REDDIT_TTLS[sort]? || OLD_REDDIT_TTLS["default"]
    end

    def self.clear_cache(subreddit : String) : Nil
      Cache.store.clear_by_prefix("reddit:#{subreddit}:")
    end

    private def self.transient_error?(kind : ErrorKind?) : Bool
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
      raise InvalidFormatError.new("Failed to parse Reddit JSON response")
    end

    private def self.extract_children(parsed : JSON::Any) : Array(JSON::Any)?
      # Reddit returns either a single listing object or an array with a listing wrapper
      listing = parsed.as_a?.try &.[]?(0).try &.["data"]? || parsed["data"]?
      listing.try(&.["children"]?).try(&.as_a?)
    rescue ex : KeyError | TypeCastError | IndexError
      ::Log.for("fetcher.reddit").warn { "Unexpected JSON structure in Reddit response: #{ex.message}" }
      nil
    end

    private def self.parse_reddit_post(child : JSON::Any) : Entry?
      post_data = extract_post_data(child) || return

      Entry.create(
        title: post_data.title,
        url: post_data.url,
        source_type: SourceType::Reddit,
        published_at: post_data.pub_date,
        is_discussion_url: post_data.link_data.is_discussion_url,
        comment_url: post_data.link_data.comment_url || post_data.discussion_url
      )
    end

    private def self.extract_post_data(child : JSON::Any) : PostData?
      post = child["data"]?
      return unless post

      discussion_url = build_discussion_url(extract_permalink(post))
      effective_url = determine_effective_url(post, discussion_url)

      PostData.new(
        title: extract_title(post),
        url: effective_url,
        discussion_url: discussion_url,
        pub_date: extract_pub_date(post),
        link_data: LinkResolver.resolve_from_url(effective_url)
      )
    end

    private def self.extract_title(post : JSON::Any) : String
      post["title"]?.try(&.as_s) || "Untitled"
    end

    private def self.extract_permalink(post : JSON::Any) : String
      post["permalink"]?.try(&.as_s) || ""
    end

    private def self.build_discussion_url(permalink : String) : String
      "https://www.reddit.com#{permalink}"
    end

    private def self.determine_effective_url(post : JSON::Any, discussion_url : String) : String
      is_self = post["is_self"]?.try(&.as_bool) || false
      post_url = post["url"]?.try(&.as_s) || ""
      is_self || post_url.empty? ? discussion_url : post_url
    end

    private def self.extract_pub_date(post : JSON::Any) : Time?
      created_utc = post["created_utc"]?.try(&.as_f) || 0.0
      created_utc > 0 ? TimeParser.normalize(Time.unix(created_utc.to_i64)) : nil
    end

    record PostData,
      title : String,
      url : String,
      discussion_url : String,
      pub_date : Time?,
      link_data : LinkResolver::LinkData
  end
end
