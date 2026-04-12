require "time"
require "mutex"

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
      @@instance ||= new
    end

    @@instance : RateLimiterRegistry? = nil

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
        RegistryHelpers.start_periodic_cleanup(60.seconds) { cleanup }
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
        now = Time.utc
        @entries.reject! { |_, entry| now - entry.last_accessed > entry.ttl }
      end
    end
  end
end
