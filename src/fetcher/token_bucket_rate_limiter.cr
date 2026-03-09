require "time"
require "mutex"

module Fetcher
  # Token bucket rate limiter implementation
  # Supports configurable capacity (burst) and refill rate
  class TokenBucketRateLimiter
    @tokens : Float64
    @capacity : Float64
    @refill_rate : Float64 # tokens per second
    @last_refill : Time
    @mutex : Mutex

    def initialize(capacity : Float64, refill_rate : Float64)
      @capacity = capacity
      @refill_rate = refill_rate
      @tokens = capacity
      @last_refill = Time.utc
      @mutex = Mutex.new
    end

    # Acquire tokens, blocking if not enough tokens are available
    def acquire(tokens : Float64 = 1.0)
      while !try_acquire(tokens)
        # Wait for tokens to be refilled
        sleep(10.milliseconds) # 10ms polling interval
      end
    end

    # Try to acquire tokens without blocking
    # Returns true if successful, false if not enough tokens
    def try_acquire(tokens : Float64 = 1.0) : Bool
      @mutex.lock
      begin
        refill_tokens
        if @tokens >= tokens
          @tokens -= tokens
          true
        else
          false
        end
      ensure
        @mutex.unlock
      end
    end

    # Get current number of available tokens
    def available_tokens : Float64
      @mutex.lock
      begin
        refill_tokens
        @tokens
      ensure
        @mutex.unlock
      end
    end

    private def refill_tokens
      now = Time.utc
      elapsed = now - @last_refill
      if elapsed > Time::Span.zero
        new_tokens = elapsed.total_seconds * @refill_rate
        @tokens = [@tokens + new_tokens, @capacity].min
        @last_refill = now
      end
    end
  end
end
