require "crest"
require "./request_config"
require "./rate_limiter_registry"
require "./circuit_breaker"
require "./safe_feed_processor"
require "./exceptions"
require "./config"
require "./url_validator"
require "./header_builder"
require "./public_suffix"

module Fetcher
  class CrestHttpClient
    alias DNSError = Fetcher::DNSError
    alias CircuitOpenError = Fetcher::CircuitOpenError
    alias MissingLocationHeaderError = Fetcher::MissingLocationHeaderError

    REDIRECT_STATUS_CODES = {301, 302, 303, 307, 308}

    @request_semaphore : Channel(Nil)?
    @semaphore_lock : Mutex = Mutex.new

    @@dns_cache = {} of String => {addr: Socket::IPAddress, expires: Time}
    @@dns_cache_lock = Mutex.new

    def initialize(@config : RequestConfig = RequestConfig.new, @validator : URLValidator::Service = URLValidator.default_service)
      # Semaphore created lazily on first request to avoid race condition
    end

    def self.clear_rate_limiters : Nil
      RateLimiterRegistry.clear
    end

    def self.clear_dns_cache : Nil
      client = new
      client.clear_dns_cache
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

    private def create_semaphore : Channel(Nil)?
      # Backwards compatibility — delegates to internal implementation
      ensure_semaphore
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
      return convert_response(response) unless should_follow_redirect?(response)

      redirect_url = extract_redirect_url(response)
      resolved_url = resolve_redirect_url(redirect_url, original_url)
      target_domain = extract_domain(resolved_url)

      validate_redirect_target(resolved_url)
      validate_redirect_domain(original_url, domain, resolved_url)
      transition_domain(domain, target_domain) if domain != target_domain
      return convert_response(response) if (remaining_redirects || @config.max_redirects) <= 1

      verify_dns_rebinding(resolved_url)
      perform_follow_redirect(method, resolved_url, headers, target_domain, remaining_redirects)
    end

    private def should_follow_redirect?(response : Crest::Response) : Bool
      REDIRECT_STATUS_CODES.includes?(response.status_code)
    end

    private def extract_redirect_url(response : Crest::Response) : String
      extract_redirect_url_from_headers(response.headers)
    end

    private def extract_redirect_url_from_headers(headers : Hash(String, String | Array(String))) : String
      redirect_url = headers["location"]? || headers["Location"]?
      raise MissingLocationHeaderError.new("Redirect response without Location header") if redirect_url.nil?

      # When headers contain multiple Location values, prefer the first one.
      value = if redirect_url.is_a?(Array)
        redirect_url.first.to_s
      else
        redirect_url.to_s
      end

      value = value.strip
      raise MissingLocationHeaderError.new("Redirect response without Location header") if value.empty?
      value
    end

    private def validate_redirect_target(url : String) : Nil
      return if @validator.valid?(url) && @validator.resolve_and_validate(url)
      # NOTE(catseye): We include the target URL in the DNSError message for diagnostics/logging.
      # This is intentional and does not execute or evaluate the URL. Treat as informational.
      raise DNSError.new("Redirect to blocked URL: #{url}")
    end

    private def validate_redirect_domain(original_url : String, source_domain : String, target_url : String) : Nil
      target_domain = @validator.extract_domain(target_url)
      return if allow_redirect?(source_domain, target_domain)
      # NOTE(catseye): We include the original and target URLs in error messages for debugging.
      # These messages are not executed or evaluated. The redirect decision is made above.
      raise DNSError.new("External redirect blocked: #{target_url} (from #{original_url})")
    end

    private def perform_follow_redirect(method : Symbol, url : String, headers : Hash(String, String), domain : String, remaining : Int32?) : ::HTTP::Client::Response
      crest_response = Crest::Request.execute(
        method,
        url,
        headers: headers,
        max_redirects: 0,
        handle_errors: false,
        connect_timeout: @config.timeout.connect,
        read_timeout: @config.timeout.read,
        tls: build_tls_context
      )
      handle_redirects(crest_response, url, headers, domain, method, remaining.try(&.- 1))
    end

    private def extract_domain(url : String) : String
      @validator.extract_domain(url)
    end

    # Check if redirect to target_domain from source_domain is allowed
    private def allow_redirect?(source_domain : String, target_domain : String) : Bool
      # Same domain is always allowed
      return true if source_domain == target_domain

      # Allow subdomain <> parent-domain redirects in either direction.
      # Examples:
      # - blog.example.com -> example.com
      # - example.com -> blog.example.com
      return true if target_domain.ends_with?(".#{source_domain}") || source_domain.ends_with?(".#{target_domain}")

      # Check redirect config
      redirect_config = @config.redirect

      # If allow_external is true, external redirects are allowed
      return true if redirect_config.allow_external

      # If allowed_domains is set, check if target is in the allowlist
      if allowed = redirect_config.allowed_domains
        # Allow exact match or subdomain of allowed domain
        return true if allowed.includes?(target_domain)
        return true if allowed.any? { |domain| target_domain.ends_with?(".#{domain}") }
      end

      # Allow if both hosts share the same registrable domain (eTLD+1)
      begin
        src_reg = PublicSuffix.registrable_domain(source_domain)
        tgt_reg = PublicSuffix.registrable_domain(target_domain)
        return true if src_reg && tgt_reg && src_reg == tgt_reg
      rescue
        # ignore errors and fall through to deny
      end

      false
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
      @@dns_cache_lock.synchronize do
        entry = @@dns_cache[host]?
        return unless entry
        if entry[:expires] > Time.utc
          entry[:addr]
        else
          @@dns_cache.delete(host)
          nil
        end
      end
    end

    private def cache_dns(host : String, addr : Socket::IPAddress) : Nil
      return unless @config.dns.cache_enabled
      ttl = @config.dns.cache_ttl
      @@dns_cache_lock.synchronize do
        @@dns_cache[host] = {addr: addr, expires: Time.utc + ttl}
      end
    end

    def clear_dns_cache : Nil
      @@dns_cache_lock.synchronize { @@dns_cache.clear }
    end


    private def verify_dns_rebinding(url : String) : Nil
      return unless should_check_dns_rebinding?

      host = extract_host(url)
      return unless host && valid_host?(host)

      if cached = get_cached_dns(host)
        validate_cached_dns(host, cached)
      else
        resolve_and_validate_new_dns(host)
      end
    rescue ex : DNSError
      raise ex
    rescue ex
      ::Log.for("fetcher").debug { "DNS rebinding check failed for #{host}: #{ex.message}" }
    end

    private def should_check_dns_rebinding? : Bool
      @config.dns.rebinding_check
    end

    private def extract_host(url : String) : String?
      URI.parse(url).host
    end

    private def valid_host?(host : String?) : Bool
      return false unless host
      !@validator.looks_like_ip?(host)
    end

    private def validate_cached_dns(host : String, cached : Socket::IPAddress) : Nil
      return if @validator.validate_connected_ip(host, cached)
      raise DNSError.new("DNS rebinding detected for #{host}: IP changed after validation")
    end

    private def resolve_and_validate_new_dns(host : String) : Nil
      addr_info = Socket::Addrinfo.resolve(host, "80", type: Socket::Type::STREAM, protocol: Socket::Protocol::TCP)
      addr_info.each do |addr|
        validate_address_for_host(host, addr) if valid_address?(addr)
      end
    end

    private def valid_address?(addr : Socket::Addrinfo) : Bool
      addr.family == Socket::Family::INET || addr.family == Socket::Family::INET6
    end

    private def validate_address_for_host(host : String, addr : Socket::Addrinfo) : Nil
      ip_address = addr.ip_address
      cache_dns(host, ip_address)
      return if @validator.validate_connected_ip(host, ip_address)
      raise DNSError.new("DNS rebinding detected for #{host}: IP changed after validation")
    end

    private def handle_error(ex : Exception, url : String)
      map_request_error(ex, url)
    end

    private def map_request_error(ex : Exception, url : String)
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
      raise DNSError.new(error.message, error, ex)
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
      raise DNSError.new(error.message, error, ex)
    end

    private def handle_request_failed(ex : Crest::RequestFailed, url : String) : Nil
      status = ex.response.status_code
      case status
      when 400..499 then handle_client_error(status, ex.message, url)
      when 500..599 then handle_server_error(status, ex.message, url)
      else               handle_http_error(status, ex.message, url)
      end
    end

    private def handle_client_error(status : Int32, message : String, url : String) : Nil
      error = Error.http(status, "HTTP #{status}: #{message}", url)
      raise HTTPClientError.new(error.message, status, error, nil)
    end

    private def handle_server_error(status : Int32, message : String, url : String) : Nil
      error = Error.server_error(status, "HTTP #{status}: #{message}", url)
      raise HTTPServerError.new(error.message, status, error, nil)
    end

    private def handle_http_error(status : Int32, message : String, url : String) : Nil
      error = Error.http(status, "HTTP #{status}: #{message}", url)
      raise HTTPError.new(error.message, status, error, nil)
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
