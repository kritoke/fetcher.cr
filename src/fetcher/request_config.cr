module Fetcher
  record RequestConfig,
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
    # Streaming parser configuration for memory efficiency
    use_streaming_parser : Bool = false,
    max_streaming_memory : Int32 = 10_485_760, # 10MB default
    debug_streaming : Bool = false do
    def delay_for_attempt(attempt : Int32) : Time::Span
      delay = base_delay * (exponential_base ** attempt)
      delay > max_delay ? max_delay : delay
    end
  end
end
