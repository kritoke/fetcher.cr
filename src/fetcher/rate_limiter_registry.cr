require "time"
require "mutex"
require "./registry_helpers"
require "./periodic_cleanup"

module Fetcher
  class RateLimiterRegistry
    record Entry,
      limiter : TokenBucketRateLimiter,
      last_accessed : Time,
      ttl : Time::Span

    DEFAULT_TTL = 5.minutes

    def self.get(domain : String, config : RequestConfig) : TokenBucketRateLimiter
      instance.get(domain, config)
    end

    def self.clear : Nil
      instance.clear
    end

    def self.cleanup : Nil
      instance.cleanup
    end

    def self.instance : RateLimiterRegistry
      @@instance_lock.synchronize { @@instance ||= new }
    end

    @@instance : RateLimiterRegistry? = nil
    @@instance_lock = Mutex.new

    @entries = {} of String => Entry
    @lock = Mutex.new

    def get(domain : String, config : RequestConfig) : TokenBucketRateLimiter
      @lock.synchronize do
        entry = @entries[domain]?
        if entry
          @entries[domain] = Entry.new(limiter: entry.limiter, last_accessed: Time.utc, ttl: entry.ttl)
          return entry.limiter
        end

        limiter = TokenBucketRateLimiter.new(
          config.rate_limit.capacity,
          config.rate_limit.refill_rate
        )
        @entries[domain] = Entry.new(limiter: limiter, last_accessed: Time.utc, ttl: DEFAULT_TTL)
        PeriodicCleanup.start_periodic_cleanup(60.seconds) { cleanup }
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
