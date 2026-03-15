require "crest"
require "./request_config"
require "./token_bucket_rate_limiter"
require "./circuit_breaker"
require "./safe_feed_processor"
require "./exceptions"

module Fetcher
  class CrestHttpClient
    DEFAULT_USER_AGENT    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    DEFAULT_ACCEPT_HEADER = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7"

    class DNSError < Exception
    end

    class CircuitOpenError < Exception
      getter domain : String

      def initialize(@domain : String)
        super("Circuit breaker open for domain: #{@domain}")
      end
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
      domain = "default"
      begin
        domain = extract_domain(url)

        check_circuit_breaker(domain)

        rate_limiter = self.class.get_token_bucket_limiter(domain, @config)
        rate_limiter.acquire

        crest_headers = build_crest_headers(headers)

        # Don't reuse HTTP clients - each request gets its own connection
        # to avoid thread-safety issues with concurrent requests
        response = Crest.head(
          url,
          headers: crest_headers,
          connect_timeout: @config.connect_timeout,
          read_timeout: @config.read_timeout
        )
        record_success(domain)
        convert_response(response)
      rescue ex : CircuitOpenError
        raise ex
      rescue ex
        record_failure(domain) unless domain.empty?
        handle_error(ex, url)
      end
    end

    def get(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Client::Response
      domain = "default"
      begin
        domain = extract_domain(url)

        check_circuit_breaker(domain)

        rate_limiter = self.class.get_token_bucket_limiter(domain, @config)
        rate_limiter.acquire

        crest_headers = build_crest_headers(headers)

        # Don't reuse HTTP clients - each request gets its own connection
        # to avoid thread-safety issues with concurrent requests
        response = Crest.get(
          url,
          headers: crest_headers,
          connect_timeout: @config.connect_timeout,
          read_timeout: @config.read_timeout
        )

        if response.body.bytesize > SafeFeedProcessor::MAX_FEED_SIZE
          raise DNSError.new("Response too large (>#{SafeFeedProcessor::MAX_FEED_SIZE / (1024 * 1024)}MB)")
        end

        record_success(domain)
        convert_response(response)
      rescue ex : CircuitOpenError
        raise ex
      rescue ex
        record_failure(domain)
        handle_error(ex, url)
      end
    end

    private def extract_domain(url : String) : String
      uri = URI.parse(url)
      uri.host || "default"
    rescue
      "default"
    end

    private def handle_error(ex : Exception, url : String)
      case ex
      when CircuitOpenError
        raise ex
      when URI::Error
        raise DNSError.new("Invalid URL: #{ex.message}")
      when Socket::Error
        raise DNSError.new("DNS/Connection error: #{ex.message}")
      when IO::TimeoutError
        raise TimeoutError.new("Timeout: #{ex.message}")
      when OpenSSL::SSL::Error
        raise DNSError.new("SSL error: #{ex.message}")
      when Crest::RequestFailed
        raise DNSError.new("HTTP error: #{ex.response.status_code}")
      else
        raise DNSError.new("Request error: #{ex.message}")
      end
    end

    private def check_circuit_breaker(domain : String) : Nil
      return unless @config.circuit_breaker_enabled

      circuit_breaker = CircuitBreaker::Registry.get(domain, @config)
      unless circuit_breaker.allow_request?
        raise CircuitOpenError.new(domain)
      end
    end

    private def record_success(domain : String) : Nil
      return unless @config.circuit_breaker_enabled

      circuit_breaker = CircuitBreaker::Registry.get(domain, @config)
      circuit_breaker.record_success
    end

    private def record_failure(domain : String) : Nil
      return unless @config.circuit_breaker_enabled

      circuit_breaker = CircuitBreaker::Registry.get(domain, @config)
      circuit_breaker.record_failure
    end

    private def convert_response(crest_response : Crest::Response) : ::HTTP::Client::Response
      ::HTTP::Client::Response.new(
        status_code: crest_response.status_code,
        body: crest_response.body,
        headers: ::HTTP::Headers.new.merge!(crest_response.headers)
      )
    end

    private def build_crest_headers(headers : ::HTTP::Headers) : Hash(String, String)
      result = HTTP::Headers{
        "User-Agent"      => DEFAULT_USER_AGENT,
        "Accept"          => DEFAULT_ACCEPT_HEADER,
        "Accept-Language" => "en-US,en;q=0.9",
        "Connection"      => "keep-alive",
      }
      result.merge!(headers)

      hash = Hash(String, String).new
      result.each do |key, value|
        hash[key] = value.is_a?(Array) ? value.join(", ") : value.to_s
      end
      hash
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
