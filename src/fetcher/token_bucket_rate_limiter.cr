require "time"
require "mutex"

module Fetcher
  class TokenBucketRateLimiter
    @tokens : Float64
    @capacity : Float64
    @refill_rate : Float64
    @last_refill : Time
    @mutex : Mutex

    def initialize(capacity : Float64, refill_rate : Float64)
      @capacity = capacity
      @refill_rate = refill_rate
      @tokens = capacity
      @last_refill = Time.utc
      @mutex = Mutex.new
    end

    def acquire(tokens : Float64 = 1.0)
      loop do
        wait_time = calculate_wait_time(tokens)
        if wt = wait_time
          sleep(wt.seconds)
        else
          return
        end
      end
    end

    private def calculate_wait_time(tokens : Float64) : Float64?
      @mutex.synchronize do
        refill_tokens
        if @tokens >= tokens
          @tokens -= tokens
          return
        end
        tokens_needed = tokens - @tokens
        wait = tokens_needed / @refill_rate
        wait < 0.001 ? 0.001 : wait
      end
    end

    def try_acquire(tokens : Float64 = 1.0) : Bool
      @mutex.synchronize do
        refill_tokens
        if @tokens >= tokens
          @tokens -= tokens
          return true
        end
        false
      end
    end

    def available_tokens : Float64
      @mutex.synchronize do
        refill_tokens
        @tokens
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
