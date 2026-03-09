require "http/client"
require "socket"
require "time"
require "mutex"
require "./request_config"
require "./token_bucket_rate_limiter"

module Fetcher
  # Unified HTTP client interface that handles all HTTP operations
  # with proper configuration, error handling, and rate limiting
  class HttpClient
    DEFAULT_USER_AGENT    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    DEFAULT_ACCEPT_HEADER = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7"

    class DNSError < Exception
    end

    @@token_bucket_limiters = {} of String => TokenBucketRateLimiter
    @@limiters_lock = Mutex.new

    def self.get_token_bucket_limiter(domain : String, config : RequestConfig) : TokenBucketRateLimiter
      @@limiters_lock.synchronize do
        @@token_bucket_limiters[domain] ||= TokenBucketRateLimiter.new(
          config.rate_limit_capacity,
          config.rate_limit_refill_rate
        )
      end
    end

    def initialize(@config : RequestConfig = RequestConfig.new)
    end

    def head(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Client::Response
      uri = URI.parse(url)

      domain = uri.host || "default"
      rate_limiter = self.class.get_token_bucket_limiter(domain, @config)
      rate_limiter.acquire

      client = ::HTTP::Client.new(uri)
      client.connect_timeout = @config.connect_timeout
      client.read_timeout = @config.read_timeout

      client.head(uri.request_target, headers: headers)
    rescue ex : URI::Error
      raise DNSError.new("Invalid URL: #{ex.message}")
    rescue ex : Socket::Error
      raise DNSError.new("DNS/Connection error: #{ex.message}")
    rescue ex : IO::TimeoutError
      raise ex
    end

    def get(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Client::Response
      uri = URI.parse(url)

      domain = uri.host || "default"
      rate_limiter = self.class.get_token_bucket_limiter(domain, @config)
      rate_limiter.acquire

      client = ::HTTP::Client.new(uri)
      client.connect_timeout = @config.connect_timeout
      client.read_timeout = @config.read_timeout
      client.compress = true

      response = client.get(uri.request_target, headers: headers)

      # Check decompressed response size to prevent compression bombs
      if response.body && response.body.bytesize > Fetcher::SafeFeedProcessor::MAX_FEED_SIZE
        raise DNSError.new("Response too large (>#{Fetcher::SafeFeedProcessor::MAX_FEED_SIZE / (1024 * 1024)}MB)")
      end

      response
    rescue ex : URI::Error
      raise DNSError.new("Invalid URL: #{ex.message}")
    rescue ex : Socket::Error
      raise DNSError.new("DNS/Connection error: #{ex.message}")
    rescue ex : IO::TimeoutError
      raise ex
    end

    def self.build_headers(custom_headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Headers
      defaults = ::HTTP::Headers{
        "User-Agent"      => DEFAULT_USER_AGENT,
        "Accept"          => DEFAULT_ACCEPT_HEADER,
        "Accept-Language" => "en-US,en;q=0.9",
        "Connection"      => "keep-alive",
      }

      result = defaults.dup
      result.merge!(custom_headers)
      result
    end

    def self.with_cache(base : ::HTTP::Headers, etag : String?, last_modified : String?) : ::HTTP::Headers
      result = base.dup
      result["If-None-Match"] = etag if etag
      result["If-Modified-Since"] = last_modified if last_modified
      result
    end
  end
end
