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
    alias MissingLocationHeaderError = Fetcher::MissingLocationHeaderError

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
      domain = URLValidator.extract_domain(url)
      acquire_semaphore
      begin
        check_circuit_breaker(domain)
        RateLimiterRegistry.get(domain, @config).acquire
        crest_headers = HeaderBuilder.build_for_crest(headers)

        verify_dns_rebinding(url)

        response = Crest::Request.execute(
          method,
          url,
          headers: crest_headers,
          max_redirects: 0,
          handle_errors: false,
          connect_timeout: @config.timeout.connect,
          read_timeout: @config.timeout.read,
          tls: build_tls_context
        )

        final_response = handle_redirects(response, url, crest_headers, domain, method)

        if method == :get && (body = final_response.body) && body.bytesize > SafeFeedProcessor::MAX_FEED_SIZE
          raise InvalidFormatError.new("Response too large (#{body.bytesize} bytes, max: #{SafeFeedProcessor::MAX_FEED_SIZE} bytes)")
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

      redirect_url = response.headers["location"]? || response.headers["Location"]?
      if redirect_url.nil? || redirect_url.empty?
        raise MissingLocationHeaderError.new("Redirect response without Location header for #{original_url}")
      end

      redirect_url_str = redirect_url.is_a?(Array) ? redirect_url.join(", ") : redirect_url.to_s
      resolved_url = resolve_redirect_url(redirect_url_str, original_url)

      unless URLValidator.valid_redirect?(resolved_url)
        raise DNSError.new("Redirect to blocked URL: #{resolved_url}")
      end

      redirect_domain = URLValidator.extract_domain(resolved_url)
      transition_domain(domain, redirect_domain) if redirect_domain != domain

      return convert_response(response) if remaining <= 1

      verify_dns_rebinding(resolved_url)

      crest_response = Crest::Request.execute(
        method,
        resolved_url,
        headers: headers,
        max_redirects: 0,
        handle_errors: false,
        connect_timeout: @config.timeout.connect,
        read_timeout: @config.timeout.read,
        tls: build_tls_context
      )

      handle_redirects(crest_response, resolved_url, headers, redirect_domain, method, remaining - 1)
    end

    private def transition_domain(from_domain : String, to_domain : String) : Nil
      check_circuit_breaker(to_domain)
      record_success(to_domain)
    end

    private def resolve_redirect_url(redirect_url : String, original_url : String) : String
      if redirect_url.starts_with?("http://") || redirect_url.starts_with?("https://")
        redirect_url
      else
        base = URI.parse(original_url)
        relative = URI.parse(redirect_url)
        resolved = base.resolve(relative)
        raise URI::Error.new("Failed to resolve redirect URL: #{redirect_url} from #{original_url}") unless resolved.host
        resolved.to_s
      end
    rescue ex
      if ex.is_a?(URI::Error)
        raise ex
      else
        raise URI::Error.new("Invalid redirect URL: #{redirect_url}")
      end
    end

    private def check_ssrf(url : String) : Nil
      unless URLValidator.valid?(url)
        raise DNSError.new("Invalid or blocked URL: #{url}")
      end
      unless URLValidator.resolve_and_validate(url)
        raise DNSError.new("SSRF check failed: URL resolved to blocked IP range: #{url}")
      end
    end

    private def verify_dns_rebinding(url : String) : Nil
      uri = URI.parse(url)
      host = uri.host
      return if host.nil? || host.empty?
      return if URLValidator.looks_like_ip?(host)

      begin
        addr_info = Socket::Addrinfo.resolve(host, "80", type: Socket::Type::STREAM, protocol: Socket::Protocol::TCP)
        addr_info.each do |addr|
          if addr.family == Socket::Family::INET || addr.family == Socket::Family::INET6
            ip_address = addr.ip_address
            unless URLValidator.validate_connected_ip(host, ip_address)
              raise DNSError.new("DNS rebinding detected for #{host}: IP changed after validation")
            end
          end
        end
      rescue ex : DNSError
        raise ex
      rescue ex
        ::Log.for("fetcher").debug { "DNS rebinding check failed for #{host}: #{ex.message}" }
      end
    end

    private def handle_error(ex : Exception, url : String)
      map_request_error(ex, url)
    end

    private def map_request_error(ex : Exception, url : String)
      case ex
      when MissingLocationHeaderError
        raise ex
      when URI::Error
        error = Error.invalid_url("Invalid URL: #{ex.message}", url)
        raise DNSError.new(error.message, error, ex)
      when Socket::Error
        error = Error.dns("DNS/Connection error: #{ex.message}", url)
        raise DNSError.new(error.message, error, ex)
      when IO::TimeoutError
        error = Error.timeout("Timeout: #{ex.message}", url)
        raise TimeoutError.new(error.message, error, ex)
      when OpenSSL::SSL::Error
        error = Error.dns("SSL error: #{ex.message}", url)
        raise DNSError.new(error.message, error, ex)
      when Crest::RequestFailed
        status = ex.response.status_code
        if (400..499).includes?(status)
          error = Error.http(status, "HTTP #{status}: #{ex.message}", url)
          raise HTTPClientError.new(error.message, status, error, ex)
        elsif (500..599).includes?(status)
          error = Error.server_error(status, "HTTP #{status}: #{ex.message}", url)
          raise HTTPServerError.new(error.message, status, error, ex)
        else
          error = Error.http(status, "HTTP #{status}: #{ex.message}", url)
          raise HTTPError.new(error.message, status, error, ex)
        end
      else
        error = Error.unknown("#{ex.class}: #{ex.message}", url)
        raise FetchError.new("Request error: #{ex.class}: #{ex.message}", error, ex)
      end
    end

    private def check_circuit_breaker(domain : String) : Nil
      return unless @config.circuit_breaker.enabled

      circuit_breaker = CircuitBreaker::Registry.get(domain, @config)
      unless circuit_breaker.allow_request?
        raise CircuitOpenError.new(domain)
      end
    end

    private def record_success(domain : String) : Nil
      return unless @config.circuit_breaker.enabled

      circuit_breaker = CircuitBreaker::Registry.get(domain, @config)
      circuit_breaker.record_success
    end

    private def record_failure(domain : String) : Nil
      return unless @config.circuit_breaker.enabled

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

    private def build_tls_context : OpenSSL::SSL::Context::Client?
      return if @config.ssl_verify?
      ensure_ssl_bypass_acknowledged
      ::Log.for("fetcher").warn { "SSL certificate verification is disabled - connections are vulnerable to MITM attacks" }
      OpenSSL::SSL::Context::Client.new.tap { |ctx| ctx.verify_mode = OpenSSL::SSL::VerifyMode::NONE }
    end

    private def ensure_ssl_bypass_acknowledged : Nil
      return if @config.responds_to?(:ssl_verify_bypass_acknowledged) && @config.ssl_verify_bypass_acknowledged
      raise InvalidURLError.new("SSL verification bypass requires explicit acknowledgment via ssl_verify_bypass_acknowledged: true in RequestConfig")
    end
  end
end
