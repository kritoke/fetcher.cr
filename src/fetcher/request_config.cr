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
    getter cache : CacheConfig
    getter max_redirects : Int32
    getter? follow_redirects : Bool
    getter? ssl_verify : Bool
    getter driver_detection_mode : DriverDetectionMode
    getter error_detail_level : ErrorDetailLevel
    getter max_concurrent_requests : Int32?

    # Support for new structured configuration
    def initialize(
      @timeout : TimeoutConfig = TimeoutConfig.new,
      @retry : RetryConfig = RetryConfig.new,
      @circuit_breaker : CircuitBreakerConfig = CircuitBreakerConfig.new,
      @rate_limit : RateLimitConfig = RateLimitConfig.new,
      @streaming : StreamingConfig = StreamingConfig.new,
      @cache : CacheConfig = CacheConfig.new,
      @max_redirects : Int32 = 5,
      @follow_redirects : Bool = true,
      @ssl_verify : Bool = true,
      @driver_detection_mode : DriverDetectionMode = DriverDetectionMode::Auto,
      @error_detail_level : ErrorDetailLevel = ErrorDetailLevel::Debug,
      @max_concurrent_requests : Int32? = nil,
    )
    end

    # Backward compatibility initializer with flat parameters
    def initialize(
      connect_timeout : Time::Span = Config::DEFAULT_CONNECT_TIMEOUT,
      read_timeout : Time::Span = Config::DEFAULT_READ_TIMEOUT,
      max_requests_per_second : Int32? = nil,
      max_concurrent_requests : Int32? = nil,
      max_redirects : Int32 = 5,
      follow_redirects : Bool = true,
      ssl_verify : Bool = true,
      http_client_pool_size : Int32? = nil,
      circuit_breaker_enabled : Bool = true,
      circuit_breaker_failure_threshold : Int32 = Config::DEFAULT_CIRCUIT_BREAKER_THRESHOLD,
      circuit_breaker_recovery_timeout : Time::Span = Config::DEFAULT_CIRCUIT_BREAKER_TIMEOUT,
      rate_limit_capacity : Float64 = Config::DEFAULT_RATE_LIMIT_CAPACITY,
      rate_limit_refill_rate : Float64 = Config::DEFAULT_RATE_LIMIT_REFILL_RATE,
      max_retries : Int32 = Config::DEFAULT_MAX_RETRIES,
      base_delay : Time::Span = Config::DEFAULT_RETRY_BASE_DELAY,
      max_delay : Time::Span = Config::DEFAULT_RETRY_MAX_DELAY,
      exponential_base : Float64 = Config::DEFAULT_RETRY_EXPONENTIAL_BASE,
      use_streaming_parser : Bool = false,
      max_streaming_memory : Int32 = 10_485_760,
      debug_streaming : Bool = false,
      cache_enabled : Bool = true,
      cache_max_size : Int32 = 1000,
      cache_default_ttl : Time::Span = Cache::DEFAULT_TTL,
      driver_detection_mode : DriverDetectionMode = DriverDetectionMode::Auto,
      error_detail_level : ErrorDetailLevel = ErrorDetailLevel::Debug,
    )
      if http_client_pool_size
        ::Log.for("fetcher").warn { "http_client_pool_size is deprecated and ignored - each request creates a new HTTP client" }
      end
      @timeout = TimeoutConfig.new(connect: connect_timeout, read: read_timeout)
      @retry = RetryConfig.new(
        max_retries: max_retries,
        base_delay: base_delay,
        max_delay: max_delay,
        exponential_base: exponential_base
      )
      @circuit_breaker = CircuitBreakerConfig.new(
        enabled: circuit_breaker_enabled,
        failure_threshold: circuit_breaker_failure_threshold,
        recovery_timeout: circuit_breaker_recovery_timeout
      )
      @rate_limit = RateLimitConfig.new(
        requests_per_second: max_requests_per_second,
        capacity: rate_limit_capacity,
        refill_rate: rate_limit_refill_rate
      )
      @streaming = StreamingConfig.new(
        enabled: use_streaming_parser,
        max_memory: max_streaming_memory,
        debug: debug_streaming
      )
      @cache = CacheConfig.new(
        enabled: cache_enabled,
        max_size: cache_max_size,
        default_ttl: cache_default_ttl
      )
      @max_redirects = max_redirects
      @follow_redirects = follow_redirects
      @ssl_verify = ssl_verify
      @driver_detection_mode = driver_detection_mode
      @error_detail_level = error_detail_level
      @max_concurrent_requests = max_concurrent_requests
    end

    # Backward compatibility methods for timeout
    def connect_timeout : Time::Span
      timeout.connect
    end

    def read_timeout : Time::Span
      timeout.read
    end

    # Backward compatibility methods for retry
    def max_retries : Int32
      retry.max_retries
    end

    def base_delay : Time::Span
      retry.base_delay
    end

    def max_delay : Time::Span
      retry.max_delay
    end

    def exponential_base : Float64
      retry.exponential_base
    end

    def delay_for_attempt(attempt : Int32) : Time::Span
      delay = base_delay * (exponential_base ** attempt)
      delay > max_delay ? max_delay : delay
    end

    # Backward compatibility methods for circuit breaker
    def circuit_breaker_enabled : Bool
      circuit_breaker.enabled
    end

    def circuit_breaker_failure_threshold : Int32
      circuit_breaker.failure_threshold
    end

    def circuit_breaker_recovery_timeout : Time::Span
      circuit_breaker.recovery_timeout
    end

    # Backward compatibility methods for rate limit
    def max_requests_per_second : Int32?
      rate_limit.requests_per_second
    end

    def rate_limit_capacity : Float64
      rate_limit.capacity
    end

    def rate_limit_refill_rate : Float64
      rate_limit.refill_rate
    end

    # Backward compatibility methods for streaming
    def use_streaming_parser : Bool
      streaming.enabled
    end

    def max_streaming_memory : Int32
      streaming.max_memory
    end

    def debug_streaming : Bool
      streaming.debug
    end

    def debug_streaming? : Bool
      streaming.debug
    end

    # Backward compatibility methods for cache
    def cache_enabled : Bool
      cache.enabled
    end

    def cache_max_size : Int32
      cache.max_size
    end

    def cache_default_ttl : Time::Span
      cache.default_ttl
    end
  end
end
