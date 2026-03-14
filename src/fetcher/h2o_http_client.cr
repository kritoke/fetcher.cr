require "h2o"
require "./request_config"
require "./token_bucket_rate_limiter"

module Fetcher
  # HTTP client using h2o library with connection pooling, circuit breaker,
  # and advanced HTTP/2 features
  class H2OHttpClient
    DEFAULT_USER_AGENT    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    DEFAULT_ACCEPT_HEADER = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7"

    class DNSError < Exception
    end

    @@token_bucket_limiters = {} of String => TokenBucketRateLimiter
    @@limiters_lock = Mutex.new

    # Shared h2o client instance with connection pooling
    @@h2o_client : H2O::Client? = nil
    @@client_lock = Mutex.new

    def self.get_token_bucket_limiter(domain : String, config : RequestConfig) : TokenBucketRateLimiter
      @@limiters_lock.synchronize do
        @@token_bucket_limiters[domain] ||= TokenBucketRateLimiter.new(
          config.rate_limit_capacity,
          config.rate_limit_refill_rate
        )
      end
    end

    def self.get_h2o_client(config : RequestConfig) : H2O::Client
      @@client_lock.synchronize do
        # Use the read timeout as the overall timeout for h2o client
        # The h2o client handles both connection and request timeouts internally
        @@h2o_client ||= H2O::Client.new(
          connection_pool_size: config.http_client_pool_size || 10,
          timeout: config.read_timeout,
          verify_ssl: config.ssl_verify,
          circuit_breaker_enabled: config.circuit_breaker_enabled
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

      h2o_client = self.class.get_h2o_client(@config)

      # Convert Crystal HTTP headers to h2o headers
      h2o_headers = H2O::Headers.new
      headers.each do |pair|
        name = pair[0]
        values = pair[1]
        # Join multiple values with comma (standard for HTTP headers)
        value = values.is_a?(Array) ? values.join(", ") : values.to_s
        h2o_headers[name] = value
      end

      response = h2o_client.head(url, h2o_headers)

      # Convert h2o response back to Crystal HTTP response
      convert_response(response, url)
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

      h2o_client = self.class.get_h2o_client(@config)

      # Convert Crystal HTTP headers to h2o headers
      h2o_headers = H2O::Headers.new
      headers.each do |pair|
        name = pair[0]
        values = pair[1]
        # Join multiple values with comma (standard for HTTP headers)
        value = values.is_a?(Array) ? values.join(", ") : values.to_s
        h2o_headers[name] = value
      end

      response = h2o_client.get(url, h2o_headers)

      # Check decompressed response size to prevent compression bombs
      if response.body && response.body.bytesize > Fetcher::SafeFeedProcessor::MAX_FEED_SIZE
        raise DNSError.new("Response too large (>#{Fetcher::SafeFeedProcessor::MAX_FEED_SIZE / (1024 * 1024)}MB)")
      end

      # Convert h2o response back to Crystal HTTP response
      convert_response(response, url)
    rescue ex : URI::Error
      raise DNSError.new("Invalid URL: #{ex.message}")
    rescue ex : Socket::Error
      raise DNSError.new("DNS/Connection error: #{ex.message}")
    rescue ex : IO::TimeoutError
      raise ex
    end

    private def convert_response(h2o_response : H2O::Response, url : String) : ::HTTP::Client::Response
      # Create Crystal HTTP response from h2o response
      crystal_response = ::HTTP::Client::Response.new(
        status_code: h2o_response.status,
        body: h2o_response.body || "",
        headers: ::HTTP::Headers.new
      )

      # Copy headers
      h2o_response.headers.each do |name, value|
        crystal_response.headers[name] = value
      end

      crystal_response
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
