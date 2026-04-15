require "time"
require "mutex"
require "./registry_helpers"
require "./periodic_cleanup"
require "./rate_limiter_store"

module Fetcher
  class RateLimiterRegistry
    record Entry,
      limiter : TokenBucketRateLimiter,
      last_accessed : Time,
      ttl : Time::Span

    DEFAULT_TTL = 5.minutes

    def self.get(domain : String, config : RequestConfig) : TokenBucketRateLimiter
      store.get(domain, config)
    end

    def self.clear : Nil
      store.clear
    end

    def self.cleanup : Nil
      store.cleanup
    end

    def self.store : RateLimiterStore
      @@store_lock.synchronize { @@store ||= RateLimiterStore.new }
    end

    @@store : RateLimiterStore? = nil
    @@store_lock = Mutex.new
  end
end
