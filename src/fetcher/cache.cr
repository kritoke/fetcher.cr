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

  class Cache
    DEFAULT_TTL = 5.minutes

    @data : Hash(String, CacheEntry) = {} of String => CacheEntry
    @access_order : Deque(String) = Deque(String).new
    @positions : Hash(String, Int32) = {} of String => Int32
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
          update_access_order(key)
          @stats.record_hit
          entry.value
        end
      end
    end

    def set(key : String, value : Result, ttl : Time::Span = DEFAULT_TTL) : Nil
      return unless @enabled

      @mutex.synchronize do
        if @data[key]?
          update_access_order(key)
          @data[key] = CacheEntry.new(value, Time.utc, ttl)
        else
          evict_if_needed
          @data[key] = CacheEntry.new(value, Time.utc, ttl)
          @access_order << key
          @positions[key] = @access_order.size - 1
        end
      end
    end

    def clear : Nil
      @mutex.synchronize do
        @data.clear
        @access_order.clear
        @positions.clear
        @stats = CacheStats.new
      end
    end

    def clear_by_prefix(prefix : String) : Nil
      @mutex.synchronize do
        keys_to_remove = @data.keys.select(&.starts_with?(prefix))
        keys_to_remove.each do |key|
          @data.delete(key)
          @positions.delete(key)
        end
        @access_order.reject! { |k| k.starts_with?(prefix) }
        reindex_positions if keys_to_remove.any?
      end
    end

    def stats : CacheStats
      @mutex.synchronize do
        CacheStats.new(
          hits: @stats.hits,
          misses: @stats.misses,
          evictions: @stats.evictions
        )
      end
    end

    private def update_access_order(key : String)
      if pos = @positions[key]?
        @access_order.delete_at(pos)
        @access_order << key
        @positions[key] = @access_order.size - 1
      else
        @access_order << key
        @positions[key] = @access_order.size - 1
      end
    end

    private def remove_entry(key : String)
      @data.delete(key)
      pos = @positions.delete(key)
      if pos
        @access_order.delete_at(pos)
        reindex_positions
      end
    end

    private def reindex_positions
      @positions.clear
      @access_order.each_with_index do |key, idx|
        @positions[key] = idx
      end
    end

    private def evict_if_needed
      while @data.size >= @max_size && !@access_order.empty?
        oldest_key = @access_order.shift?
        if oldest_key
          @positions.delete(oldest_key)
          @data.delete(oldest_key)
          @stats.record_eviction
          reindex_positions
        end
      end
    end

    # Shared instance for backward compatibility
    @@default : Cache? = nil

    def self.default : Cache
      @@default ||= new
    end

    # Backward-compatible class methods (delegates to default instance)
    def self.get(key : String) : Result?
      default.get(key)
    end

    def self.set(key : String, value : Result, ttl : Time::Span = DEFAULT_TTL) : Nil
      default.set(key, value, ttl)
    end

    def self.clear : Nil
      default.clear
    end

    def self.clear_by_prefix(prefix : String) : Nil
      default.clear_by_prefix(prefix)
    end

    def self.stats : CacheStats
      default.stats
    end

    def self.enabled? : Bool
      default.enabled?
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

    # Backward-compatible Reddit helpers (deprecated: use Reddit module instead)
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
