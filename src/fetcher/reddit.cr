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
require "./version"
require "./reddit_diagnostics"
require "./reddit_post_parser"

module Fetcher
  module Reddit
    USER_AGENT          = "fetcher.cr/#{Fetcher::VERSION} (https://github.com/kritoke/fetcher.cr; 3081486+kritoke@users.noreply.github.com)"
    REDDIT_API_BASE     = "https://www.reddit.com"
    OLD_REDDIT_API_BASE = "https://old.reddit.com"

    # Diagnostics and response formatting constants

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

    private def self.fetch_fallback(subreddit : String, sort : String, limit : Int32, headers : ::HTTP::Headers, config : RequestConfig) : NamedTuple(result: Result, source: Symbol)
      old_config = config.with_retry_max_retries(2)
      run_strategies(
        subreddit,
        api: -> { attempt_with_retry(config) { fetch_reddit_api(subreddit, sort, limit, headers, config) } },
        rss: -> { fetch_rss(subreddit, sort, limit, headers, config) },
        old_reddit: -> { attempt_with_retry(old_config) { fetch_reddit_api(subreddit, sort, limit, headers, old_config, OLD_REDDIT_API_BASE) } },
      )
    end

    # :nodoc:
    # Runs API -> RSS (on 403 or transient API errors) -> old.reddit. When all
    # fail, the error leads with the primary API failure so a blocked server
    # is not misreported as "Subreddit not found" (old.reddit's 404).
    def self.run_strategies(subreddit : String, api : -> Result, rss : -> Result, old_reddit : -> Result) : NamedTuple(result: Result, source: Symbol)
      api_result = api.call
      return {result: api_result, source: :api} if api_result.success?
      api_error = api_result.error

      rss_error = nil
      if api_error && (api_error.status_code == 403 || transient_error?(api_error.kind))
        ::Log.for("fetcher.reddit").warn { "Reddit API returned #{short_error(api_error)} for /r/#{subreddit} - trying RSS fallback" }
        rss_result = rss.call
        return {result: rss_result, source: :rss} if rss_result.success?
        rss_error = rss_result.error
        ::Log.for("fetcher.reddit").warn { "Reddit RSS fallback failed for /r/#{subreddit}: #{rss_error.try { |err| short_error(err) } || "unknown error"}" }
      end

      old_result = old_reddit.call
      return {result: old_result, source: :old_reddit} if old_result.success?

      {result: Result.error(combined_error(subreddit, api_error, rss_error, old_result.error)), source: :failed}
    end

    # :nodoc:
    # `Fetcher.with_retry` flattens exceptions into `Error.unknown`, dropping
    # the HTTP status the fallback decision depends on. Capture the structured
    # error from the last attempt and return it instead.
    def self.attempt_with_retry(config : RequestConfig, &block : -> Result) : Result
      last_error = nil.as(Error?)
      result = Fetcher.with_retry(config) do
        block.call
      rescue ex : RedditFetchError
        last_error = structured_error(ex)
        raise ex
      end
      return result if result.success?
      if err = last_error
        Result.error(err)
      else
        result
      end
    end

    private def self.structured_error(ex : RedditFetchError) : Error
      cause = ex.original_cause
      if cause.is_a?(FetchError) && (original = cause.original_error)
        original
      elsif cause.is_a?(HTTPError) && (status = cause.status_code)
        Error.http(status, ex.message)
      else
        Error.unknown(ex.message || "Reddit API failed")
      end
    end

    private def self.short_error(err : Error) : String
      case err.status_code
      when 403   then "blocked request (HTTP 403)"
      when Int32 then "HTTP #{err.status_code}"
      else            err.message
      end
    end

    private def self.combined_error(subreddit : String, api : Error?, rss : Error?, old : Error?) : Error
      if api && api.status_code == 404
        return Error.invalid_url("Subreddit '#{subreddit}' not found", api.url)
      end

      parts = ["Reddit API failed for /r/#{subreddit}: #{api.try { |err| short_error(err) } || "unknown error"}"]
      rss.try { |err| parts << "RSS fallback: #{short_error(err)}" }
      old.try { |err| parts << "old.reddit: #{short_error(err)}" }
      Error.new(
        kind: api.try(&.kind) || ErrorKind::Unknown,
        message: parts.join("; "),
        status_code: api.try(&.status_code),
        url: api.try(&.url),
      )
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
      RedditDiagnostics.log_fetch(api_url, final_headers)

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
        detail = RedditDiagnostics.build_response_detail(response)
        ::Log.for("fetcher.reddit").warn { "Reddit API returned non-OK status: #{detail} for #{api_url}" }

        error = Error.http(response.status_code, "HTTP error #{response.status_code}: #{detail}", api_url)
        raise HTTPError.new(error.message, response.status_code, error)
      end
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
      RedditPostParser.parse(body, limit)
    end
  end
end
