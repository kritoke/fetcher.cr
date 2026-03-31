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
    getter hits : UInt64
    getter misses : UInt64
    getter evictions : UInt64

    def initialize(@hits = 0_u64, @misses = 0_u64, @evictions = 0_u64)
    end

    def hit_ratio : Float64
      total = @hits + @misses
      total > 0 ? @hits.to_f / total : 0.0
    end

    def record_hit
      @hits += 1
    end

    def record_miss
      @misses += 1
    end

    def record_eviction
      @evictions += 1
    end

    def to_s : String
      "CacheStats(hits: #{@hits}, misses: #{@misses}, evictions: #{@evictions}, hit_ratio: #{(hit_ratio * 100).round(2)}%)"
    end
  end

  module Cache
    @@data : Hash(String, CacheEntry) = {} of String => CacheEntry
    @@access_order : Deque(String) = Deque(String).new
    @@positions : Hash(String, Int32) = {} of String => Int32
    @@mutex : Mutex = Mutex.new
    @@stats : CacheStats = CacheStats.new
    @@max_size : Int32 = 1000
    @@enabled : Bool = true

    DEFAULT_TTL = 5.minutes

    NEW_POSTS_TTL           = 30.seconds
    RISING_POSTS_TTL        = 30.seconds
    HOT_POSTS_TTL           = 2.minutes
    TOP_POSTS_TTL           = 10.minutes
    CONTROVERSIAL_POSTS_TTL = 10.minutes

    def self.enabled? : Bool
      @@enabled
    end

    def self.enabled=(value : Bool)
      @@enabled = value
    end

    def self.max_size : Int32
      @@max_size
    end

    def self.max_size=(value : Int32)
      @@max_size = value
    end

    def self.get(key : String) : Result?
      return unless @@enabled

      @@mutex.synchronize do
        entry = @@data[key]?
        if entry
          if entry.expired?
            remove_entry(key)
            @@stats.record_miss
            return
          end
          update_access_order(key)
          @@stats.record_hit
          return entry.value
        end
        @@stats.record_miss
        nil
      end
    end

    def self.set(key : String, value : Result, ttl : Time::Span = DEFAULT_TTL) : Nil
      return unless @@enabled

      @@mutex.synchronize do
        if @@data[key]?
          update_access_order(key)
          @@data[key] = CacheEntry.new(value, Time.utc, ttl)
        else
          evict_if_needed
          @@data[key] = CacheEntry.new(value, Time.utc, ttl)
          @@access_order << key
          @@positions[key] = @@access_order.size - 1
        end
      end
    end

    def self.clear : Nil
      @@mutex.synchronize do
        @@data.clear
        @@access_order.clear
        @@positions.clear
        @@stats = CacheStats.new
      end
    end

    def self.clear_subreddit(subreddit : String) : Nil
      @@mutex.synchronize do
        pattern = "fetcher:reddit:#{subreddit}:"
        keys_to_remove = @@data.keys.select(&.starts_with?(pattern))
        keys_to_remove.each do |key|
          remove_entry(key)
        end
      end
    end

    def self.stats : CacheStats
      @@mutex.synchronize do
        CacheStats.new(
          hits: @@stats.hits,
          misses: @@stats.misses,
          evictions: @@stats.evictions
        )
      end
    end

    def self.ttl_for_sort(sort : String) : Time::Span
      case sort
      when "new"
        NEW_POSTS_TTL
      when "rising"
        RISING_POSTS_TTL
      when "hot"
        HOT_POSTS_TTL
      when "top"
        TOP_POSTS_TTL
      when "controversial"
        CONTROVERSIAL_POSTS_TTL
      else
        DEFAULT_TTL
      end
    end

    def self.generate_key(subreddit : String, sort : String, limit : Int32) : String
      "fetcher:reddit:#{subreddit}:#{sort}:#{limit}"
    end

    private def self.update_access_order(key : String)
      if pos = @@positions[key]?
        @@access_order.delete_at(pos)
        @@access_order << key
        @@positions[key] = @@access_order.size - 1
      else
        @@access_order << key
        @@positions[key] = @@access_order.size - 1
      end
    end

    private def self.remove_entry(key : String)
      @@data.delete(key)
      pos = @@positions.delete(key)
      if pos
        @@access_order.delete_at(pos)
        reindex_positions
      end
    end

    private def self.reindex_positions
      @@positions.clear
      @@access_order.each_with_index do |key, idx|
        @@positions[key] = idx
      end
    end

    private def self.evict_if_needed
      while @@data.size >= @@max_size && !@@access_order.empty?
        oldest_key = @@access_order.shift?
        if oldest_key
          @@positions.delete(oldest_key)
          @@data.delete(oldest_key)
          @@stats.record_eviction
          reindex_positions
        end
      end
    end
  end
end
