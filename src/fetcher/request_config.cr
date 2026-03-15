module Fetcher
  record RequestConfig,
    connect_timeout : Time::Span = 10.seconds,
    read_timeout : Time::Span = 30.seconds,
    max_requests_per_second : Int32? = nil,
    max_concurrent_requests : Int32? = nil,
    max_redirects : Int32 = 5,
    follow_redirects : Bool = true,
    ssl_verify : Bool = true,
    http_client_pool_size : Int32? = nil,
    circuit_breaker_enabled : Bool = true,
    circuit_breaker_failure_threshold : Int32 = 5,
    circuit_breaker_recovery_timeout : Time::Span = 60.seconds,
    rate_limit_capacity : Float64 = 10.0,
    rate_limit_refill_rate : Float64 = 1.0,
    max_retries : Int32 = 3,
    base_delay : Time::Span = 1.second,
    max_delay : Time::Span = 30.seconds,
    exponential_base : Float64 = 2.0,
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
