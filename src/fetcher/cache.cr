require "time"
require "mutex"
require "./cache_store"

module Fetcher
  struct CacheEntry
    getter value : Result
    getter timestamp : Time
    getter ttl : Time::Span

    def initialize(@value : Result, @timestamp : Time, @ttl : Time::Span)
    end

    def expired? : Bool
      Time.utc - @timestamp > @ttl
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
    # Cache API. We keep a default store instance for backward compatibility.
    def self.store : CacheStore
      @@store_lock.synchronize { @@store ||= CacheStore.new }
    end

    @@store : CacheStore? = nil
    @@store_lock = Mutex.new

    def self.default : CacheStore
      store
    end

    # Keep instance constructor compatible with existing tests / usage that
    # create Cache instances. Instances are lightweight facades over the
    # shared store.
    def initialize(@max_size : Int32 = 1000, @enabled : Bool = true)
      # Instance-local store preserves the original per-instance behavior.
      @store = CacheStore.new(@max_size, @enabled)
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

    def self.generate_key(subreddit : String, sort : String, limit : Int32) : String
      Reddit.generate_cache_key(subreddit, sort, limit)
    end

    def self.ttl_for_sort(sort : String) : Time::Span
      Reddit.ttl_for_sort(sort)
    end

    def self.clear_subreddit(subreddit : String) : Nil
      Reddit.clear_cache(subreddit)
    end
  end
end
