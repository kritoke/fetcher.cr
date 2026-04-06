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
    @cleanup_running = false
    @cleanup_lock = Mutex.new

    def get(domain : String, config : RequestConfig) : TokenBucketRateLimiter
      @lock.synchronize do
        entry = @entries[domain]?
        if entry
          @entries[domain] = Entry.new(
            limiter: entry.limiter,
            last_accessed: Time.utc,
            ttl: entry.ttl
          )
          return entry.limiter
        end

        limiter = TokenBucketRateLimiter.new(
          config.rate_limit.capacity,
          config.rate_limit.refill_rate
        )
        @entries[domain] = Entry.new(
          limiter: limiter,
          last_accessed: Time.utc,
          ttl: DEFAULT_TTL
        )
        start_cleanup_if_needed
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
        @entries.reject! do |_, entry|
          now - entry.last_accessed > entry.ttl
        end
      end
    end

    def start_cleanup_if_needed : Nil
      @cleanup_lock.synchronize do
        return if @cleanup_running
        @cleanup_running = true
      end
      spawn do
        begin
          loop do
            sleep 60.seconds
            cleanup
          end
        rescue ex
          ::Log.for("fetcher").warn { "Rate limiter cleanup fiber error: #{ex.class} - #{ex.message}" }
          @cleanup_lock.synchronize { @cleanup_running = false }
        end
      end
    end
  end
end
