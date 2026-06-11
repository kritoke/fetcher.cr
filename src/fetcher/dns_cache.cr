require "socket"
require "./periodic_cleanup"

module Fetcher
  # Process-wide DNS resolution cache.
  #
  # Owns its own lock, size cap, and one-shot periodic-cleanup registration.
  # Lookup/store are no-ops when the caller signals `cache_enabled? == false`,
  # so the gate check happens in exactly one place per public method.
  class DnsCache
    # Eviction buffer - remove this many entries above the configured cap
    # in a single sweep so we don't evict on every insert at the boundary.
    EVICTION_BUFFER = 100

    # Default size cap for the cache when no explicit value is configured.
    DEFAULT_MAX_ENTRIES = 10_000

    @@cache = {} of String => {addr: Socket::IPAddress, expires: Time}
    @@lock = Mutex.new
    @@max_entries : Int32 = DEFAULT_MAX_ENTRIES
    @@cleanup_registered = false

    # Configure the maximum number of cache entries. Call once during app init.
    def self.max_entries : Int32
      @@max_entries
    end

    def self.max_entries=(value : Int32) : Nil
      @@max_entries = value
    end

    # Lookup a cached address for `host`. Returns nil if not cached, expired,
    # or the caller has not enabled caching.
    def self.lookup(host : String, cache_enabled? : Bool) : Socket::IPAddress?
      return unless cache_enabled?
      @@lock.synchronize do
        entry = @@cache[host]?
        return unless entry
        if entry[:expires] > Time.utc
          entry[:addr]
        else
          @@cache.delete(host)
          nil
        end
      end
    end

    # Store `addr` for `host` with the given TTL. No-op when caching is
    # disabled. Registers the periodic cleanup exactly once.
    def self.store(host : String, addr : Socket::IPAddress, ttl : Time::Span, cache_enabled? : Bool) : Nil
      return unless cache_enabled?
      @@lock.synchronize do
        ensure_cleanup_registered
        enforce_limit
        @@cache[host] = {addr: addr, expires: Time.utc + ttl}
      end
    end

    # Drop every entry. Intended for tests and operator-driven resets.
    def self.clear : Nil
      @@lock.synchronize { @@cache.clear }
    end

    # Drop expired entries. Invoked periodically by `PeriodicCleanup`.
    def self.clear_expired : Nil
      @@lock.synchronize do
        now = Time.utc
        @@cache.reject! { |_, entry| entry[:expires] <= now }
      end
    end

    # Enforce max_entries + EVICTION_BUFFER. Caller must hold @@lock.
    # Public so CrestHttpClient can delegate its `enforce_dns_limit` shim.
    def self.enforce_limit : Nil
      return unless @@cache.size >= @@max_entries
      target_size = @@max_entries + EVICTION_BUFFER
      while @@cache.size > target_size
        key = @@cache.keys.sample
        @@cache.delete(key) if key
      end
    end

    # Register the periodic cleanup exactly once. Caller must hold @@lock.
    # Public so CrestHttpClient can delegate its `ensure_dns_cleanup_registered` shim.
    def self.ensure_cleanup_registered : Nil
      return if @@cleanup_registered
      @@cleanup_registered = true
      PeriodicCleanup.register_cleanup { clear_expired }
    end
  end
end
