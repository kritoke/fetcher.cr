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
    requests_per_second : Int32? = nil,
    capacity : Float64 = Config::DEFAULT_RATE_LIMIT_CAPACITY,
    refill_rate : Float64 = Config::DEFAULT_RATE_LIMIT_REFILL_RATE

  record StreamingConfig,
    enabled : Bool = false,
    max_memory : Int32 = 10_485_760, # 10MB default
    debug : Bool = false

  record CacheConfig,
    enabled : Bool = true,
    max_size : Int32 = 1000,
    default_ttl : Time::Span = Cache::DEFAULT_TTL

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
    getter max_redirects : Int32
    getter? follow_redirects : Bool
    getter? ssl_verify : Bool
    getter driver_detection_mode : DriverDetectionMode
    getter error_detail_level : ErrorDetailLevel
    getter max_concurrent_requests : Int32?
    getter ssl_verify_bypass_acknowledged : Bool

    @cache_instance : Cache? = nil

    def cache : Cache
      @cache_instance ||= Cache.new(
        max_size: @cache_config.max_size,
        enabled: @cache_config.enabled
      )
    end

    def initialize(
      @timeout : TimeoutConfig = TimeoutConfig.new,
      @retry : RetryConfig = RetryConfig.new,
      @circuit_breaker : CircuitBreakerConfig = CircuitBreakerConfig.new,
      @rate_limit : RateLimitConfig = RateLimitConfig.new,
      @streaming : StreamingConfig = StreamingConfig.new,
      @cache_config : CacheConfig = CacheConfig.new,
      @max_redirects : Int32 = 5,
      @follow_redirects : Bool = true,
      @ssl_verify : Bool = true,
      @driver_detection_mode : DriverDetectionMode = DriverDetectionMode::Auto,
      @error_detail_level : ErrorDetailLevel = ErrorDetailLevel::Normal,
      @max_concurrent_requests : Int32? = nil,
      @ssl_verify_bypass_acknowledged : Bool = false,
    )
    end

    def delay_for_attempt(attempt : Int32) : Time::Span
      capped_attempt = Math.min(attempt, 30)
      delay = retry.base_delay * (retry.exponential_base ** capped_attempt)
      delay > retry.max_delay ? retry.max_delay : delay
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
        max_redirects: @max_redirects,
        follow_redirects: @follow_redirects,
        ssl_verify: @ssl_verify,
        driver_detection_mode: @driver_detection_mode,
        error_detail_level: @error_detail_level,
        max_concurrent_requests: @max_concurrent_requests,
        ssl_verify_bypass_acknowledged: @ssl_verify_bypass_acknowledged
      )
    end
  end
end
