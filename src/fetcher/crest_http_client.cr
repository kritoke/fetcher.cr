require "crest"
require "./request_config"
require "./token_bucket_rate_limiter"
require "./circuit_breaker"
require "./safe_feed_processor"
require "./exceptions"
require "./config"
require "./url_validator"

module Fetcher
  class CrestHttpClient
    DEFAULT_USER_AGENT    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    DEFAULT_ACCEPT_HEADER = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7"

    alias DNSError = Fetcher::DNSError
    alias CircuitOpenError = Fetcher::CircuitOpenError

    record LimiterEntry,
      limiter : TokenBucketRateLimiter,
      last_accessed : Time,
      ttl : Time::Span

    @@limiter_entries = {} of String => LimiterEntry
    @@limiters_lock = Mutex.new
    @@limiter_cleanup_running = false

    @request_semaphore : Channel(Nil)?

    def self.clear_rate_limiters : Nil
      @@limiters_lock.synchronize do
        @@limiter_entries.clear
      end
    end

    def initialize(@config : RequestConfig = RequestConfig.new)
      @request_semaphore = create_semaphore
    end

    private def create_semaphore : Channel(Nil)?
      limit = @config.max_concurrent_requests
      return unless limit && limit > 0

      sem = Channel(Nil).new(limit)
      # Pre-fill the semaphore with tokens
      limit.times { sem.send(nil) }
      sem
    end

    private def acquire_semaphore : Nil
      sem = @request_semaphore
      return unless sem
      sem.receive
    end

    private def release_semaphore : Nil
      sem = @request_semaphore
      return unless sem
      sem.send(nil)
    end

    REDIRECT_STATUS_CODES = {301, 302, 303, 307, 308}

    def head(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Client::Response
      check_ssrf(url)

      domain = extract_domain(url)

      acquire_semaphore
      begin
        check_circuit_breaker(domain)

        rate_limiter = self.class.get_token_bucket_limiter(domain, @config)
        rate_limiter.acquire

        crest_headers = build_crest_headers(headers)

        response = Crest.head(
          url,
          headers: crest_headers,
          max_redirects: 0,
          handle_errors: false,
          connect_timeout: @config.connect_timeout,
          read_timeout: @config.read_timeout
        )

        final_response = handle_redirects(response, url, crest_headers, domain, :head)
        record_success(domain)
        final_response
      rescue ex : CircuitOpenError
        raise ex
      rescue ex
        record_failure(domain) unless domain.empty?
        handle_error(ex, url)
      ensure
        release_semaphore
      end
    end

    def get(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Client::Response
      check_ssrf(url)

      domain = extract_domain(url)

      acquire_semaphore
      begin
        check_circuit_breaker(domain)

        rate_limiter = self.class.get_token_bucket_limiter(domain, @config)
        rate_limiter.acquire

        crest_headers = build_crest_headers(headers)

        response = Crest.get(
          url,
          headers: crest_headers,
          max_redirects: 0,
          handle_errors: false,
          connect_timeout: @config.connect_timeout,
          read_timeout: @config.read_timeout
        )

        final_response = handle_redirects(response, url, crest_headers, domain, :get)

        if final_response.body.bytesize > SafeFeedProcessor::MAX_FEED_SIZE
          raise InvalidFormatError.new("Response too large (#{final_response.body.bytesize} bytes, max: #{SafeFeedProcessor::MAX_FEED_SIZE} bytes)")
        end

        record_success(domain)
        final_response
      rescue ex : CircuitOpenError
        raise ex
      rescue ex
        record_failure(domain)
        handle_error(ex, url)
      ensure
        release_semaphore
      end
    end

    private def handle_redirects(response : Crest::Response, original_url : String, headers : Hash(String, String), domain : String, method : Symbol) : ::HTTP::Client::Response
      return convert_response(response) unless REDIRECT_STATUS_CODES.includes?(response.status_code)

      redirect_url = response.headers["Location"]?
      if redirect_url.nil? || redirect_url.empty?
        raise DNSError.new("Redirect response without Location header for #{original_url}")
      end

      redirect_url_str = redirect_url.is_a?(Array) ? redirect_url.join(", ") : redirect_url.to_s
      resolved_url = resolve_redirect_url(redirect_url_str, original_url)

      unless URLValidator.valid_redirect?(resolved_url)
        raise DNSError.new("Redirect to blocked URL: #{resolved_url}")
      end

      redirect_domain = extract_domain(resolved_url)
      if redirect_domain != domain
        record_success(domain)
        check_circuit_breaker(redirect_domain)
        self.class.get_token_bucket_limiter(redirect_domain, @config).acquire
        record_failure(domain) unless domain.empty?
        record_success(redirect_domain)
      end

      remaining_redirects = @config.max_redirects - 1
      if remaining_redirects <= 0
        return convert_response(response)
      end

      crest_response = Crest::Request.execute(
        method,
        resolved_url,
        headers: headers,
        max_redirects: 0,
        handle_errors: false,
        connect_timeout: @config.connect_timeout,
        read_timeout: @config.read_timeout
      )

      handle_redirects(crest_response, resolved_url, headers, redirect_domain, method)
    end

    private def resolve_redirect_url(redirect_url : String, original_url : String) : String
      if redirect_url.starts_with?("http://") || redirect_url.starts_with?("https://")
        redirect_url
      else
        uri = URI.parse(original_url)
        base = "#{uri.scheme}://#{uri.host}"
        base += ":#{uri.port}" if uri.port && uri.port != 80 && uri.port != 443
        File.join(base, redirect_url)
      end
    end

    private def extract_domain(url : String) : String
      uri = URI.parse(url)
      uri.host || "default"
    rescue
      "default"
    end

    private def check_ssrf(url : String) : Nil
      unless URLValidator.valid?(url)
        raise DNSError.new("Invalid or blocked URL: #{url}")
      end
      unless URLValidator.resolve_and_validate(url)
        raise DNSError.new("URL resolves to blocked IP address: #{url}")
      end
    end

    private def handle_error(ex : Exception, url : String)
      case ex
      when URI::Error
        raise DNSError.new("Invalid URL: #{ex.message}")
      when Socket::Error
        raise DNSError.new("DNS/Connection error: #{ex.message}")
      when IO::TimeoutError
        raise TimeoutError.new("Timeout: #{ex.message}")
      when OpenSSL::SSL::Error
        raise DNSError.new("SSL error: #{ex.message}")
      when Crest::RequestFailed
        status = ex.response.status_code
        if (400..499).includes?(status)
          raise HTTPClientError.new("HTTP #{status}: #{ex.message}", status, nil)
        elsif (500..599).includes?(status)
          raise HTTPServerError.new("HTTP #{status}: #{ex.message}", status, nil)
        else
          raise HTTPError.new("HTTP #{status}: #{ex.message}", status, nil)
        end
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

    def self.get_token_bucket_limiter(domain : String, config : RequestConfig) : TokenBucketRateLimiter
      @@limiters_lock.synchronize do
        entry = @@limiter_entries[domain]?
        if entry
          @@limiter_entries[domain] = LimiterEntry.new(
            limiter: entry.limiter,
            last_accessed: Time.utc,
            ttl: entry.ttl
          )
          return entry.limiter
        end

        limiter = TokenBucketRateLimiter.new(
          config.rate_limit_capacity,
          config.rate_limit_refill_rate
        )
        @@limiter_entries[domain] = LimiterEntry.new(
          limiter: limiter,
          last_accessed: Time.utc,
          ttl: 5.minutes
        )
        start_limiter_cleanup
        limiter
      end
    end

    def self.cleanup_limiters : Nil
      @@limiters_lock.synchronize do
        now = Time.utc
        @@limiter_entries.reject! do |_, entry|
          now - entry.last_accessed > entry.ttl
        end
      end
    end

    private def self.start_limiter_cleanup : Nil
      return if @@limiter_cleanup_running
      @@limiter_cleanup_running = true
      spawn do
        loop do
          sleep 60.seconds
          cleanup_limiters
        end
      end
    end
  end
end
