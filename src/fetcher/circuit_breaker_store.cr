require "time"
require "mutex"
require "./registry_helpers"
require "./periodic_cleanup"
require "./periodic_cleanup_handle"
require "./circuit_breaker"

module Fetcher
  class CircuitBreakerStore
    record Entry,
      breaker : CircuitBreaker,
      last_accessed : Time::Span,
      ttl : Time::Span

    DEFAULT_TTL = 5.minutes

    @cleanup_handle : PeriodicCleanupHandle

    def initialize(@max_entries : Int32 = 10_000)
      @entries = {} of String => Entry
      @lock = Mutex.new
      @cleanup_handle = PeriodicCleanupHandle.new
    end

    def get(domain : String, config) : CircuitBreaker
      @lock.synchronize do
        entry = @entries[domain]?
        if entry
          @entries[domain] = Entry.new(breaker: entry.breaker, last_accessed: Time.monotonic, ttl: entry.ttl)
          return entry.breaker
        end

        # Enforce size limit before creating new entry to prevent unbounded growth
        if @entries.size >= @max_entries
          enforce_limit
        end

        breaker = CircuitBreaker.new(
          failure_threshold: config.circuit_breaker.failure_threshold,
          recovery_timeout: config.circuit_breaker.recovery_timeout
        )
        entry = Entry.new(breaker: breaker, last_accessed: Time.monotonic, ttl: DEFAULT_TTL)
        @entries[domain] = entry

        # Register cleanup exactly once per store instance, not per domain.
        @cleanup_handle.register { cleanup }
        breaker
      end
    end



    def clear : Nil
      @lock.synchronize do
        @entries.clear
      end
    end

    def all_states : Hash(String, {CircuitBreaker::State, Int32})
      @lock.synchronize do
        @entries.transform_values { |entry| {entry.breaker.state, entry.breaker.failure_count} }
      end
    end

    def cleanup : Nil
      @lock.synchronize do
        BoundedRegistry.cleanup(@entries)
      end
    end

    # Proactively sweep all expired entries from the store.
    # Call this periodically (e.g., every few minutes) to prevent memory growth
    # from stale entries that haven't been accessed since expiration.
    def clear_expired : Nil
      @lock.synchronize do
        now = Time.monotonic
        @entries.reject! do |_, entry|
          entry.last_accessed + entry.ttl < now
        end
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
