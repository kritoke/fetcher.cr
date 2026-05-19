require "time"
require "mutex"
require "./cache_store"

module Fetcher
  struct CacheEntry
    getter value : Result
    getter last_accessed : Time
    getter ttl : Time::Span

    def initialize(@value : Result, @last_accessed : Time, @ttl : Time::Span)
    end

    def expired? : Bool
      Time.utc - @last_accessed > @ttl
    end
  end

  struct CacheStats
    @hits : Atomic(UInt64)
    @misses : Atomic(UInt64)
    @evictions : Atomic(UInt64)

    def initialize(
      @hits : Atomic(UInt64) = Atomic.new(0_u64),
      @misses : Atomic(UInt64) = Atomic.new(0_u64),
      @evictions : Atomic(UInt64) = Atomic.new(0_u64),
    )
    end

    def self.snapshot(hits : UInt64, misses : UInt64, evictions : UInt64) : CacheStats
      new(hits: Atomic.new(hits), misses: Atomic.new(misses), evictions: Atomic.new(evictions))
    end

    def hit_ratio : Float64
      hits = @hits.get
      total = hits + @misses.get
      total > 0 ? hits.to_f / total : 0.0
    end

    def record_hit : Nil
      @hits.add(1)
    end

    def record_miss : Nil
      @misses.add(1)
    end

    def record_eviction : Nil
      @evictions.add(1)
    end

    def hits : UInt64
      @hits.get
    end

    def misses : UInt64
      @misses.get
    end

    def evictions : UInt64
      @evictions.get
    end

    def to_s : String
      "CacheStats(hits: #{@hits.get}, misses: #{@misses.get}, evictions: #{@evictions.get}, hit_ratio: #{(hit_ratio * 100).round(2)}%)"
    end
  end

  class Cache
    DEFAULT_TTL = 5.minutes

    # Store-based implementation to own mutation while preserving the existing
    # Cache API. There are two levels of cache in this library:
    # - Class-level (shared) store: used by Cache.class methods (Cache.set/get/clear)
    # - Instance-level store: each Cache.new(...) produces a lightweight facade
    #   backed by its own CacheStore instance. This preserves backwards
    #   compatibility with callers that expect isolated caches.
    #
    # To avoid accidental confusion, the constructor explicitly accepts
    # keyword arguments (max_size, enabled). Class-level access is provided by
    # the `store` helper below.
    @@store : CacheStore? = nil
    @@store_lock = Mutex.new

    def self.store : CacheStore
      @@store_lock.synchronize { @@store ||= CacheStore.new }
    end

    # Replace the default/shared store used by class-level Cache methods.
    # This allows applications to inject a shared CacheStore instance for
    # global caching without relying on global state construction.
    def self.default_store=(store : CacheStore)
      @@store_lock.synchronize { @@store = store }
    end

    # Note: prefer the `default_store=` accessor. Older callers using
    # `set_default_store` should be updated to `default_store=`.

    # Convenience: create and set a shared default store with the provided
    # configuration.
    def self.use_default_store(max_size : Int32 = 1000, enabled : Bool = true) : Nil
      @@store_lock.synchronize { @@store = CacheStore.new(max_size, enabled) }
    end

    def self.default : CacheStore
      store
    end

    # Keep instance constructor compatible with existing tests / usage that
    # create Cache instances. Instances are lightweight facades over their own
    # CacheStore so tests and callers that expect isolated caches continue to
    # work.
    # Constructor: keep backwards-compatible signature but allow injecting a
    # CacheStore. If `store` is provided, the Cache instance will wrap that
    # store (useful for sharing a store across many Cache instances). If not
    # provided, a new per-instance CacheStore is created (preserves legacy
    # behavior).
    def initialize(max_size : Int32 = 1000, enabled : Bool = true, store : CacheStore? = nil)
      @max_size = max_size
      @enabled = enabled
      @store = store || CacheStore.new(@max_size, @enabled)
    end

    # Instance API (delegate to the instance-local store)
    def get(key : String) : Result?
      @store.get(key)
    end

    def set(key : String, value : Result, ttl : Time::Span = DEFAULT_TTL)
      @store.set(key, value, ttl)
    end

    def clear
      @store.clear
    end

    def clear_by_prefix(prefix : String)
      @store.clear_by_prefix(prefix)
    end

    def stats : CacheStats
      @store.stats
    end

    def enabled? : Bool
      @store.enabled?
    end

    def enabled=(value : Bool)
      @store.enabled = value
    end

    def max_size : Int32
      @store.max_size
    end

    def max_size=(value : Int32)
      @store.max_size = value
    end

    {% for method, ret in {
                            "get"             => "Result?",
                            "clear"           => "Void",
                            "clear_by_prefix" => "Void",
                            "stats"           => "CacheStats",
                            "enabled?"        => "Bool",
                            "max_size"        => "Int32",
                          } %}
      def self.{{ method.id }}(*args) : {{ ret.id }}
        store.{{ method.id }}(*args)
      end
    {% end %}

    def self.set(key : String, value : Result, ttl : Time::Span = DEFAULT_TTL) : Nil
      store.set(key, value, ttl)
    end

    def self.enabled=(value : Bool)
      store.enabled = value
    end

    def self.max_size=(value : Int32)
      store.max_size = value
    end
  end
end
