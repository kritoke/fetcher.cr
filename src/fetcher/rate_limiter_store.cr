require "./registry_store"
require "./token_bucket_rate_limiter"

module Fetcher
  # Encapsulated store for rate limiters. Localizes mutation and locking so the
  # public RateLimiterRegistry can remain a thin facade.
  class RateLimiterStore < RegistryStore(TokenBucketRateLimiter)
    def create_value(config) : TokenBucketRateLimiter
      TokenBucketRateLimiter.new(
        config.rate_limit.capacity,
        config.rate_limit.refill_rate,
        config.rate_limit.max_waiter_queue_size || 1000
      )
    end
  end
end
