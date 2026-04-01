require "crest"
require "./request_config"
require "./rate_limiter_registry"
require "./circuit_breaker"
require "./safe_feed_processor"
require "./exceptions"
require "./config"
require "./url_validator"
require "./header_builder"

module Fetcher
  class CrestHttpClient
    alias DNSError = Fetcher::DNSError
    alias CircuitOpenError = Fetcher::CircuitOpenError

    REDIRECT_STATUS_CODES = {301, 302, 303, 307, 308}

    @request_semaphore : Channel(Nil)?

    def initialize(@config : RequestConfig = RequestConfig.new)
      @request_semaphore = create_semaphore
    end

    def self.clear_rate_limiters : Nil
      RateLimiterRegistry.clear
    end

    def head(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Client::Response
      perform_request(:head, url, headers)
    end

    def get(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Client::Response
      perform_request(:get, url, headers)
    end

    def self.build_headers(custom_headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Headers
      HeaderBuilder.build(custom_headers)
    end

    def self.with_cache(base : ::HTTP::Headers, etag : String?, last_modified : String?) : ::HTTP::Headers
      result = base.dup
      result["If-None-Match"] = etag if etag
      result["If-Modified-Since"] = last_modified if last_modified
      result
    end

    private def create_semaphore : Channel(Nil)?
      limit = @config.max_concurrent_requests
      return unless limit && limit > 0

      sem = Channel(Nil).new(limit)
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

    private def perform_request(method : Symbol, url : String, headers : ::HTTP::Headers) : ::HTTP::Client::Response
      check_ssrf(url)
      domain = extract_domain(url)
      acquire_semaphore
      begin
        check_circuit_breaker(domain)
        RateLimiterRegistry.get(domain, @config).acquire
        crest_headers = HeaderBuilder.build_for_crest(headers)

        response = Crest::Request.execute(
          method,
          url,
          headers: crest_headers,
          max_redirects: 0,
          handle_errors: false,
          connect_timeout: @config.connect_timeout,
          read_timeout: @config.read_timeout
        )

        final_response = handle_redirects(response, url, crest_headers, domain, method)

        if method == :get && final_response.body.bytesize > SafeFeedProcessor::MAX_FEED_SIZE
          raise InvalidFormatError.new("Response too large (#{final_response.body.bytesize} bytes, max: #{SafeFeedProcessor::MAX_FEED_SIZE} bytes)")
        end

        record_success(domain)
        final_response
      rescue ex
        record_failure(domain) unless domain.empty?
        handle_error(ex, url)
      ensure
        release_semaphore
      end
    end

    private def handle_redirects(response : Crest::Response, original_url : String, headers : Hash(String, String), domain : String, method : Symbol, remaining_redirects : Int32? = nil) : ::HTTP::Client::Response
      remaining = remaining_redirects || @config.max_redirects
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
      transition_domain(domain, redirect_domain) if redirect_domain != domain

      return convert_response(response) if remaining <= 1

      crest_response = Crest::Request.execute(
        method,
        resolved_url,
        headers: headers,
        max_redirects: 0,
        handle_errors: false,
        connect_timeout: @config.connect_timeout,
        read_timeout: @config.read_timeout
      )

      handle_redirects(crest_response, resolved_url, headers, redirect_domain, method, remaining - 1)
    end

    private def transition_domain(from_domain : String, to_domain : String) : Nil
      check_circuit_breaker(to_domain)
      RateLimiterRegistry.get(to_domain, @config).acquire
      record_success(to_domain)
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
  end
end
