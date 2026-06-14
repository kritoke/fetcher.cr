require "time"
require "mutex"
require "./registry_helpers"
require "./periodic_cleanup"
require "./rate_limiter_store"
require "./lazy_store"

module Fetcher
  class RateLimiterRegistry
    lazy_store(RateLimiterStore)

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
  end
end
