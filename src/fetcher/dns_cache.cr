require "socket"
require "./periodic_cleanup"

module Fetcher
  # Process-wide DNS resolution cache.
  #
  # Owns its own lock, size cap, and one-shot periodic-cleanup registration.
  # Pure storage abstraction: the cache does not know about the caller's
  # cache_enabled policy. Callers gate before calling (see
  # `CrestHttpClient#get_cached_dns` and `#cache_dns`).
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
      raise ArgumentError.new("max_entries must be positive, got #{value}") if value <= 0
      @@max_entries = value
    end

    # Lookup a cached address for `host`. Returns nil if not cached or
    # expired. Pure read: does not mutate the cache. Expired entries
    # remain in the cache until `clear_expired` removes them.
    # `PeriodicCleanup` runs `clear_expired` on a fixed interval (60s by
    # default) so the cache is bounded in practice.
    #
    # The cache is a pure storage abstraction; enabling/disabling caching
    # is the caller's responsibility (see `CrestHttpClient#get_cached_dns`).
    def self.lookup(host : String) : Socket::IPAddress?
      @@lock.synchronize do
        entry = @@cache[host]?
        return unless entry
        entry[:expires] > Time.utc ? entry[:addr] : nil
      end
    end

    # Store `addr` for `host` with the given TTL. Registers the periodic
    # cleanup exactly once.
    #
    # The cache is a pure storage abstraction; enabling/disabling caching
    # is the caller's responsibility (see `CrestHttpClient#cache_dns`).
    def self.store(host : String, addr : Socket::IPAddress, ttl : Time::Span) : Nil
      @@lock.synchronize do
        ensure_cleanup_registered_unlocked
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

    # Register the periodic cleanup exactly once. Public, self-locking.
    # Safe to call from anywhere (the CrestHttpClient shim, application
    # init code, tests). Internally split from the unlocked helper because
    # Crystal's Mutex is not re-entrant and `store` already holds the lock
    # when it registers.
    def self.ensure_cleanup_registered : Nil
      @@lock.synchronize { ensure_cleanup_registered_unlocked }
    end

    # Internal helper. Caller must hold @@lock.
    private def self.ensure_cleanup_registered_unlocked : Nil
      return if @@cleanup_registered
      @@cleanup_registered = true
      PeriodicCleanup.register_cleanup { clear_expired }
    end
  end
end
