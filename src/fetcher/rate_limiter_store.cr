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
      last_accessed : Time::Span,
      ttl : Time::Span

    DEFAULT_TTL = 5.minutes

    @cleanup_proc : Proc(Nil)?
    @cleanup_registered : Bool

    def initialize(@max_entries : Int32 = 10_000)
      @entries = {} of String => Entry
      @lock = Mutex.new
      @cleanup_proc = nil
      @cleanup_registered = false
    end

    private def cleanup_proc : Proc(Nil)
      @cleanup_proc ||= Proc(Nil).new { cleanup }
    end

    def get(domain : String, config : RequestConfig) : TokenBucketRateLimiter
      @lock.synchronize do
        entry = @entries[domain]?
        if entry
          @entries[domain] = Entry.new(limiter: entry.limiter, last_accessed: Time.monotonic, ttl: entry.ttl)
          return entry.limiter
        end

        # Enforce size limit before creating new entry to prevent unbounded growth
        if @entries.size >= @max_entries
          enforce_limit
        end

        limiter = TokenBucketRateLimiter.new(
          config.rate_limit.capacity,
          config.rate_limit.refill_rate,
          config.rate_limit.max_waiter_queue_size || 1000
        )
        @entries[domain] = Entry.new(limiter: limiter, last_accessed: Time.monotonic, ttl: DEFAULT_TTL)

        # Register cleanup exactly once per store instance, not per domain.
        # The cleanup proc is cached in @cleanup_proc and reused for all domains.
        register_store_cleanup
        limiter
      end
    end

    # Register this store's cleanup proc exactly once.
    private def register_store_cleanup : Nil
      return if @cleanup_registered
      @cleanup_registered = true
      PeriodicCleanup.register_cleanup { cleanup_proc.call }
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

    # Enforce size limit by removing oldest entries when at capacity
    private def enforce_limit : Nil
      # Convert to array for sorting (Hash doesn't have sort_by)
      sorted = @entries.to_a.sort_by { |_, entry| entry.last_accessed }
      # Remove buffer of 100 entries to avoid hitting limit repeatedly
      excess_count = [@entries.size - @max_entries + 100, sorted.size].min
      excess_count.times do
        if entry = sorted.shift?
          oldest_key, _ = entry
          @entries.delete(oldest_key)
        end
      end
    end
  end
end
