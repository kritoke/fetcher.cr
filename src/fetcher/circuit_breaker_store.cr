require "time"
require "mutex"
require "./registry_helpers"
require "./periodic_cleanup"
require "./circuit_breaker"

module Fetcher
  class CircuitBreakerStore
    record Entry,
      breaker : CircuitBreaker,
      last_accessed : Time,
      ttl : Time::Span

    DEFAULT_TTL = 5.minutes

    def initialize(@max_entries : Int32 = 10_000)
      @entries = {} of String => Entry
      @lock = Mutex.new
    end

    def get(domain : String, config) : CircuitBreaker
      @lock.synchronize do
        entry = @entries[domain]?
        if entry
          @entries[domain] = Entry.new(breaker: entry.breaker, last_accessed: Time.utc, ttl: entry.ttl)
          return entry.breaker
        end

        breaker = CircuitBreaker.new(
          failure_threshold: config.circuit_breaker.failure_threshold,
          recovery_timeout: config.circuit_breaker.recovery_timeout
        )
        entry = Entry.new(breaker: breaker, last_accessed: Time.utc, ttl: DEFAULT_TTL)
        @entries[domain] = entry
        PeriodicCleanup.start_periodic_cleanup(60.seconds) { cleanup }
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
  end
end
