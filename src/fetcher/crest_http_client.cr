require "crest"
require "compress/gzip"
require "./request_config"
require "./rate_limiter_registry"
require "./circuit_breaker"
require "./safe_feed_processor"
require "./exceptions"
require "./config"
require "./url_validator"
require "./header_builder"
require "./public_suffix"
require "./crest_http_client/redirect_policy"
require "./crest_http_client/rebinding_checker"

module Fetcher
  class CrestHttpClient
    alias DNSError = Fetcher::DNSError
    alias CircuitOpenError = Fetcher::CircuitOpenError
    alias MissingLocationHeaderError = Fetcher::MissingLocationHeaderError

    @request_semaphore : Channel(Nil)?
    @semaphore_lock : Mutex = Mutex.new
    @policy : RedirectPolicy

    # DNS cache lookup/store are private instance methods below. The cache
    # itself, its lock, eviction policy, and periodic-cleanup registration
    # all live in DnsCache.

    @rebinding_checker : RebindingChecker

    def initialize(@config : RequestConfig = RequestConfig.new, @validator : URLValidator::Service = URLValidator.default_service)
      @policy = RedirectPolicy.new(@config, @validator)
      @rebinding_checker = RebindingChecker.new(@config, @validator)
      # Semaphore created lazily on first request to avoid race condition
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
      HeaderBuilder.with_cache(base, etag, last_modified)
    end

    private def ensure_semaphore : Channel(Nil)?
      existing = @request_semaphore
      return existing if existing

      @semaphore_lock.synchronize do
        @request_semaphore ||= create_semaphore_internal
      end
    end

    private def create_semaphore_internal : Channel(Nil)?
      limit = @config.max_concurrent_requests
      return unless limit && limit > 0

      sem = Channel(Nil).new(limit)
      limit.times { sem.send(nil) }
      sem
    end

    private def acquire_semaphore : Nil
      sem = ensure_semaphore
      return unless sem
      sem.receive
    end

    private def release_semaphore : Nil
      sem = ensure_semaphore
      return unless sem
      sem.send(nil)
    end

    private def perform_request(method : Symbol, url : String, headers : ::HTTP::Headers) : ::HTTP::Client::Response
      check_ssrf(url)
      domain = @validator.extract_domain(url)
      acquire_semaphore
      begin
        check_circuit_breaker(domain)
        RateLimiterRegistry.get(domain, @config).acquire
        crest_headers = HeaderBuilder.build_for_crest(headers)

        verify_dns_rebinding(url)

        response = execute_crest(method, url, crest_headers)

        final_response = handle_redirects(response, url, crest_headers, domain, method)

        # NOTE: response-size check was removed from this layer (see fetcherc-9el.6).
        # CrestHttpClient is now feed-agnostic; feed-parsing drivers own size limits.
        # The constant SafeFeedProcessor::MAX_FEED_SIZE is now used only by
        # SafeFeedProcessor itself (which the feed drivers do not currently invoke
        # in production -- a separate follow-up is needed to wire that in).

        record_success(domain)
        final_response
      rescue ex : HTTPClientError
        # 4xx client errors are not transient server issues — don't circuit-break
        handle_error(ex, url)
      rescue ex
        record_failure(domain) unless domain.empty?
        handle_error(ex, url)
      ensure
        release_semaphore
      end
    end

    private def handle_redirects(response : Crest::Response, original_url : String, headers : Hash(String, String), domain : String, method : Symbol, remaining_redirects : Int32? = nil) : ::HTTP::Client::Response
      return convert_response(response) unless @policy.follow?(response)

      redirect_url = @policy.extract_url(response)
      resolved_url = @policy.resolve(redirect_url, original_url)
      target_domain = @validator.extract_domain(resolved_url)

      @policy.validate_target(resolved_url)
      @policy.validate_domain(original_url, domain, resolved_url, target_domain, response.status_code)
      preflight_redirect_target(domain, target_domain) if domain != target_domain
      return convert_response(response) if (remaining_redirects || @config.max_redirects) <= 1

      verify_dns_rebinding(resolved_url)
      perform_follow_redirect(method, resolved_url, headers, target_domain, remaining_redirects)
    end

    private def perform_follow_redirect(method : Symbol, url : String, headers : Hash(String, String), domain : String, remaining : Int32?) : ::HTTP::Client::Response
      crest_response = execute_crest(method, url, headers)
      # Record the successful HTTP exchange with the target as soon as it
      # returns. This is the natural place: the response was just received
      # from this domain, regardless of whether the chain continues.
      record_success(domain)
      handle_redirects(crest_response, url, headers, domain, method, remaining.try(&.- 1))
    end

    # Single source of truth for the underlying Crest::Request.execute call.
    # Both perform_request and perform_follow_redirect funnel through here so
    # request-shape changes (timeouts, TLS, headers, etc.) only need to be made
    # in one place.
    private def execute_crest(method : Symbol, url : String, headers : Hash(String, String)) : Crest::Response
      Crest::Request.execute(
        method,
        url,
        headers: headers,
        max_redirects: 0,
        handle_errors: false,
        connect_timeout: @config.timeout.connect,
        read_timeout: @config.timeout.read,
        tls: build_tls_context
      )
    end

    private def preflight_redirect_target(from_domain : String, to_domain : String) : Nil
      # Pre-flight: if the target's circuit breaker is open, fail fast before
      # issuing the redirected request. Success recording is the responsibility
      # of the request path that actually completes contact with the target.
      check_circuit_breaker(to_domain)
    end

    private def check_ssrf(url : String) : Nil
      unless @validator.valid?(url)
        # NOTE(catseye): including the url in these DNSError messages is for logging/diagnostics only.
        # Input is validated above and not executed.
        raise DNSError.new("Invalid or blocked URL: #{url}")
      end
      unless @validator.resolve_and_validate(url)
        # NOTE(catseye): SSRF detection reports the URL in the error message for operators.
        raise DNSError.new("SSRF check failed: URL resolved to blocked IP range: #{url}")
      end
    end

    private def get_cached_dns(host : String) : Socket::IPAddress?
      return unless @config.dns.cache_enabled
      DnsCache.lookup(host)
    end

    private def cache_dns(host : String, addr : Socket::IPAddress) : Nil
      return unless @config.dns.cache_enabled
      DnsCache.store(host, addr, @config.dns.cache_ttl)
    end

    def clear_dns_cache : Nil
      DnsCache.clear
    end


    private def verify_dns_rebinding(url : String) : Nil
      @rebinding_checker.verify(url)
    end

    private def handle_error(ex : Exception, url : String)
      case ex
      when MissingLocationHeaderError then raise ex
      when URI::Error                 then handle_uri_error(ex, url)
      when Socket::Error              then handle_socket_error(ex, url)
      when IO::TimeoutError           then handle_timeout_error(ex, url)
      when OpenSSL::SSL::Error        then handle_ssl_error(ex, url)
      when Crest::RequestFailed       then handle_request_failed(ex, url)
      else                                 handle_unknown_error(ex, url)
      end
    end

    private def handle_uri_error(ex : URI::Error, url : String) : Nil
      # NOTE(catseye): We create an Error object that includes the URL for clarity in logs.
      # This does not perform any execution of the URL content.
      error = Error.invalid_url("Invalid URL: #{ex.message}", url)
      raise InvalidURLError.new(error.message, error, ex)
    end

    private def handle_socket_error(ex : Socket::Error, url : String) : Nil
      # NOTE(catseye): DNS/connection errors include the URL/host in messages for diagnostics.
      error = Error.dns("DNS/Connection error: #{ex.message}", url)
      raise DNSError.new(error.message, error, ex)
    end

    private def handle_timeout_error(ex : IO::TimeoutError, url : String) : Nil
      error = Error.timeout("Timeout: #{ex.message}", url)
      raise TimeoutError.new(error.message, error, ex)
    end

    private def handle_ssl_error(ex : OpenSSL::SSL::Error, url : String) : Nil
      error = Error.dns("SSL error: #{ex.message}", url)
      raise SSLError.new(error.message, error, ex)
    end

    private def handle_request_failed(ex : Crest::RequestFailed, url : String) : Nil
      status = ex.response.status_code
      message = "HTTP #{status}: #{ex.message}"

      # Classify once and derive both the structured Error and the wrapper
      # exception. Keeping the status range check in one place prevents the
      # 4xx/5xx/other branches from drifting apart between the two paths.
      error, wrapper_class = case status
                             when 400..499 then {Error.http(status, message, url), HTTPClientError}
                             when 500..599 then {Error.server_error(status, message, url), HTTPServerError}
                             else               {Error.http(status, message, url), HTTPError}
                             end

      raise wrapper_class.new(error.message, status, error, nil)
    end

    private def handle_unknown_error(ex : Exception, url : String) : Nil
      # NOTE(catseye): Unknown errors bubble up with the URL included for debugging. This is
      # informational only and not an execution vector.
      error = Error.unknown("#{ex.class}: #{ex.message}", url)
      raise FetchError.new("Request error: #{ex.class}: #{ex.message}", error, ex)
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
      body = CrestHttpClient.ensure_decompressed(crest_response.body)
      ::HTTP::Client::Response.new(
        status_code: crest_response.status_code,
        body: body,
        headers: ::HTTP::Headers.new.merge!(crest_response.headers)
      )
    end

    # Defensive decompression: some servers (especially behind CDNs like
    # Vercel/Cloudflare) send gzip-compressed bodies without a proper
    # Content-Encoding header. Crystal's auto-decompress relies on that
    # header, so we check for gzip magic bytes (\x1f\x08b) manually.
    def self.ensure_decompressed(body : String) : String
      return body unless body.bytesize >= 2

      bytes = body.to_slice
      return body unless bytes[0] == 0x1f_u8 && bytes[1] == 0x8b_u8

      ::Log.for("fetcher.http").info { "Decompressing gzip body (missing Content-Encoding header)" }
      io = IO::Memory.new(body)
      Compress::Gzip::Reader.open(io) do |gzip|
        gzip.gets_to_end
      end
    rescue ex
      ::Log.for("fetcher.http").warn { "Failed to decompress gzip body: #{ex.message}" }
      body
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
