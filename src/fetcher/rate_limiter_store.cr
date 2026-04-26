require "time"
require "mutex"
require "./token_bucket_rate_limiter"
require "./registry_helpers"
require "./periodic_cleanup"

module Fetcher
  # Encapsulated store for rate limiters. Localizes mutation and locking so the
  # public RateLimiterRegistry can remain a thin facade.
  class RateLimiterStore
    record Entry,
      limiter : TokenBucketRateLimiter,
      last_accessed : Time,
      ttl : Time::Span

    DEFAULT_TTL = 5.minutes

    def initialize(@max_entries : Int32 = 10_000)
      @entries = {} of String => Entry
      @lock = Mutex.new
    end

    def get(domain : String, config : RequestConfig) : TokenBucketRateLimiter
      @lock.synchronize do
        entry = @entries[domain]?
        if entry
          @entries[domain] = Entry.new(limiter: entry.limiter, last_accessed: Time.utc, ttl: entry.ttl)
          return entry.limiter
        end

        limiter = TokenBucketRateLimiter.new(
          config.rate_limit.capacity,
          config.rate_limit.refill_rate,
          config.rate_limit.max_waiter_queue_size || 1000
        )
        @entries[domain] = Entry.new(limiter: limiter, last_accessed: Time.utc, ttl: DEFAULT_TTL)
        PeriodicCleanup.register_cleanup { cleanup }
        limiter
      end
    end

    def clear : Nil
      @lock.synchronize do
        @entries.clear
      end
    end

    def cleanup : Nil
      @lock.synchronize do
        BoundedRegistry.cleanup(@entries)
      end
    end
  end
end
