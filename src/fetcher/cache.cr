require "time"
require "mutex"

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

    def hit_ratio : Float64
      total = @hits.get + @misses.get
      total > 0 ? @hits.get.to_f / total : 0.0
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

    @data : Hash(String, CacheEntry) = {} of String => CacheEntry
    @eviction_order : Deque(String) = Deque(String).new
    @eviction_set : Set(String) = Set(String).new
    @mutex : Mutex = Mutex.new
    @stats : CacheStats = CacheStats.new
    @max_size : Int32 = 1000
    @enabled : Bool = true

    def initialize(@max_size : Int32 = 1000, @enabled : Bool = true)
    end

    def enabled? : Bool
      @enabled
    end

    def enabled=(value : Bool)
      @enabled = value
    end

    def max_size : Int32
      @max_size
    end

    def max_size=(value : Int32)
      @max_size = value
    end

    def get(key : String) : Result?
      return unless @enabled

      @mutex.synchronize do
        entry = @data[key]?
        if entry.nil?
          @stats.record_miss
          nil
        elsif entry.expired?
          remove_entry(key)
          @stats.record_miss
          nil
        else
          @stats.record_hit
          entry.value
        end
      end
    end

    def set(key : String, value : Result, ttl : Time::Span = DEFAULT_TTL) : Nil
      return unless @enabled

      @mutex.synchronize do
        if @data[key]?
          @data[key] = CacheEntry.new(value, Time.utc, ttl)
          @eviction_order.reject! { |k| k == key }
          @eviction_set.delete(key)
          @eviction_order << key
          @eviction_set.add(key)
        else
          evict_if_needed
          @data[key] = CacheEntry.new(value, Time.utc, ttl)
          @eviction_order << key
          @eviction_set.add(key)
        end
      end
    end

    def clear : Nil
      @mutex.synchronize do
        @data.clear
        @eviction_order.clear
        @eviction_set.clear
        @stats = CacheStats.new
      end
    end

    def clear_by_prefix(prefix : String) : Nil
      @mutex.synchronize do
        keys_to_remove = [] of String
        @data.each_key do |key|
          keys_to_remove << key if key.starts_with?(prefix)
        end
        keys_to_remove.each do |key|
          @data.delete(key)
          @eviction_set.delete(key)
        end
        @eviction_order.reject!(&.starts_with?(prefix))
      end
    end

    def stats : CacheStats
      @mutex.synchronize do
        CacheStats.new(
          hits: Atomic.new(@stats.hits),
          misses: Atomic.new(@stats.misses),
          evictions: Atomic.new(@stats.evictions)
        )
      end
    end

    private def remove_entry(key : String)
      @data.delete(key)
      @eviction_set.delete(key)
      @eviction_order.reject! { |k| k == key }
    end

    private def evict_if_needed
      while @data.size >= @max_size && !@eviction_order.empty?
        oldest_key = @eviction_order.shift?
        if oldest_key
          @data.delete(oldest_key)
          @eviction_set.delete(oldest_key)
          @stats.record_eviction
        end
      end
    end

    # Shared instance for backward compatibility
    @@default : Cache? = nil
    @@default_lock = Mutex.new

    def self.default : Cache
      @@default_lock.synchronize { @@default ||= new }
    end

    {% for method, ret in {
                            "get"             => "Result?",
                            "clear"           => "Void",
                            "clear_by_prefix" => "Void",
                            "stats"           => "CacheStats",
                            "enabled?"        => "Bool",
                          } %}
      def self.{{ method.id }}(*args) : {{ ret.id }}
        default.{{ method.id }}(*args)
      end
    {% end %}

    def self.set(key : String, value : Result, ttl : Time::Span = DEFAULT_TTL) : Nil
      default.set(key, value, ttl)
    end

    def self.enabled=(value : Bool)
      default.enabled = value
    end

    def self.max_size : Int32
      default.max_size
    end

    def self.max_size=(value : Int32)
      default.max_size = value
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
