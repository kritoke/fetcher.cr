module Fetcher
  record TimeoutConfig,
    connect : Time::Span = Config::DEFAULT_CONNECT_TIMEOUT,
    read : Time::Span = Config::DEFAULT_READ_TIMEOUT

  record RetryConfig,
    max_retries : Int32 = Config::DEFAULT_MAX_RETRIES,
    base_delay : Time::Span = Config::DEFAULT_RETRY_BASE_DELAY,
    max_delay : Time::Span = Config::DEFAULT_RETRY_MAX_DELAY,
    exponential_base : Float64 = Config::DEFAULT_RETRY_EXPONENTIAL_BASE

  record CircuitBreakerConfig,
    enabled : Bool = true,
    failure_threshold : Int32 = Config::DEFAULT_CIRCUIT_BREAKER_THRESHOLD,
    recovery_timeout : Time::Span = Config::DEFAULT_CIRCUIT_BREAKER_TIMEOUT

  record RateLimitConfig,
    capacity : Float64 = Config::DEFAULT_RATE_LIMIT_CAPACITY,
    refill_rate : Float64 = Config::DEFAULT_RATE_LIMIT_REFILL_RATE,
    max_waiter_queue_size : Int32? = nil

  record DnsConfig,
    cache_enabled : Bool = false,
    cache_ttl : Time::Span = 30.seconds,
    rebinding_check : Bool = true

  record StreamingConfig,
    enabled : Bool = false,
    max_memory : Int32 = 10_485_760, # 10MB default
    debug : Bool = false

  record CacheConfig,
    enabled : Bool = true,
    max_size : Int32 = 1000,
    default_ttl : Time::Span = Cache::DEFAULT_TTL

  # Content extraction configuration
  # strip_entry_content: if true, entry HTML content is not extracted/parsed.
  #   Saves memory when only metadata (title, url, published_at) is needed.
  record ContentConfig,
    strip_entry_content : Bool = false

  # Redirect security configuration
  # allow_external: if false (default), redirects to external domains are blocked
  # allowed_domains: optional allowlist of specific domains for external redirects
  # allow_permanent_external: if true (default), 301/308 permanent redirects to external
  #   domains are allowed. These represent the resource URL moving permanently (e.g.
  #   blog relocations from blogspot.com to custom domains).
  record RedirectConfig,
    allow_external : Bool = false,
    allowed_domains : Array(String)? = nil,
    allow_permanent_external : Bool = true

  enum DriverDetectionMode
    Auto
    ContentType
    UrlOnly
    ExplicitOnly
  end

  enum ErrorDetailLevel
    Minimal
    Normal
    Debug
  end

  class RequestConfig
    getter timeout : TimeoutConfig
    getter retry : RetryConfig
    getter circuit_breaker : CircuitBreakerConfig
    getter rate_limit : RateLimitConfig
    getter streaming : StreamingConfig
    getter cache_config : CacheConfig
    getter dns : DnsConfig
    getter content : ContentConfig
    getter redirect : RedirectConfig
    getter max_redirects : Int32
    getter? follow_redirects : Bool
    getter? ssl_verify : Bool
    getter driver_detection_mode : DriverDetectionMode
    getter error_detail_level : ErrorDetailLevel
    getter max_concurrent_requests : Int32?
    getter ssl_verify_bypass_acknowledged : Bool
    getter gitlab_token : String?
    getter codeberg_token : String?
    getter reddit_client_id : String?
    getter reddit_client_secret : String?
    getter reddit_username : String?
    getter reddit_password : String?

    @cache_instance : Cache? = nil

    def cache : Cache
      # Construct Cache using positional args to match Cache.new signature
      @cache_instance ||= Cache.new(@cache_config.max_size, @cache_config.enabled)
    end

    def initialize(
      @timeout : TimeoutConfig = TimeoutConfig.new,
      @retry : RetryConfig = RetryConfig.new,
      @circuit_breaker : CircuitBreakerConfig = CircuitBreakerConfig.new,
      @rate_limit : RateLimitConfig = RateLimitConfig.new,
      @streaming : StreamingConfig = StreamingConfig.new,
      @cache_config : CacheConfig = CacheConfig.new,
      @dns : DnsConfig = DnsConfig.new,
      @content : ContentConfig = ContentConfig.new,
      @redirect : RedirectConfig = RedirectConfig.new,
      @max_redirects : Int32 = 5,
      @follow_redirects : Bool = true,
      @ssl_verify : Bool = true,
      @driver_detection_mode : DriverDetectionMode = DriverDetectionMode::Auto,
      @error_detail_level : ErrorDetailLevel = ErrorDetailLevel::Normal,
      @max_concurrent_requests : Int32? = nil,
      @ssl_verify_bypass_acknowledged : Bool = false,
      @gitlab_token : String? = nil,
      @codeberg_token : String? = nil,
      @reddit_client_id : String? = nil,
      @reddit_client_secret : String? = nil,
      @reddit_username : String? = nil,
      @reddit_password : String? = nil,
    )
    end

    def delay_for_attempt(attempt : Int32) : Time::Span
      capped_attempt = Math.min(attempt, Config::RETRY_MAX_ATTEMPT_CAP)
      delay = retry.base_delay * (retry.exponential_base ** capped_attempt)
      Math.min(delay, retry.max_delay)
    end

    # Return a copy of this RequestConfig with the retry.max_retries overridden.
    # This avoids constructing a new RequestConfig by copying every field manually.
    def with_retry_max_retries(max_retries : Int32) : RequestConfig
      new_retry = RetryConfig.new(
        max_retries: max_retries,
        base_delay: @retry.base_delay,
        max_delay: @retry.max_delay,
        exponential_base: @retry.exponential_base
      )

      RequestConfig.new(
        timeout: @timeout,
        retry: new_retry,
        circuit_breaker: @circuit_breaker,
        rate_limit: @rate_limit,
        streaming: @streaming,
        cache_config: @cache_config,
        dns: @dns,
        content: @content,
        redirect: @redirect,
        max_redirects: @max_redirects,
        follow_redirects: @follow_redirects,
        ssl_verify: @ssl_verify,
        driver_detection_mode: @driver_detection_mode,
        error_detail_level: @error_detail_level,
        max_concurrent_requests: @max_concurrent_requests,
        ssl_verify_bypass_acknowledged: @ssl_verify_bypass_acknowledged,
        gitlab_token: @gitlab_token,
        codeberg_token: @codeberg_token,
        reddit_client_id: @reddit_client_id,
        reddit_client_secret: @reddit_client_secret,
        reddit_username: @reddit_username,
        reddit_password: @reddit_password
      )
    end

    # Return a copy of this RequestConfig with specific allowed domains for redirects.
    def with_redirect_allowed_domains(domains : Array(String)) : RequestConfig
      new_redirect = RedirectConfig.new(
        allow_external: @redirect.allow_external,
        allowed_domains: domains,
        allow_permanent_external: @redirect.allow_permanent_external
      )

      RequestConfig.new(
        timeout: @timeout,
        retry: @retry,
        circuit_breaker: @circuit_breaker,
        rate_limit: @rate_limit,
        streaming: @streaming,
        cache_config: @cache_config,
        dns: @dns,
        content: @content,
        redirect: new_redirect,
        max_redirects: @max_redirects,
        follow_redirects: @follow_redirects,
        ssl_verify: @ssl_verify,
        driver_detection_mode: @driver_detection_mode,
        error_detail_level: @error_detail_level,
        max_concurrent_requests: @max_concurrent_requests,
        ssl_verify_bypass_acknowledged: @ssl_verify_bypass_acknowledged,
        gitlab_token: @gitlab_token,
        codeberg_token: @codeberg_token,
        reddit_client_id: @reddit_client_id,
        reddit_client_secret: @reddit_client_secret,
        reddit_username: @reddit_username,
        reddit_password: @reddit_password
      )
    end

    # Close resources held by this config, including the Cache owner fiber.
    # Call this when the config is no longer needed to prevent fiber leaks.
    def close : Nil
      @cache_instance.try(&.close)
    end
  end
end
