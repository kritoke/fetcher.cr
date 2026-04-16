require "time"
require "mutex"
require "./registry_helpers"
require "./periodic_cleanup"

module Fetcher
  # Actor-backed cache store that owns mutation for cache entries, eviction and stats.
  class CacheStore
    record GetMsg, key : String, reply : Channel(Result?)
    record SetMsg, key : String, value : Result, ttl : Time::Span
    record ClearMsg
    record ClearByPrefixMsg, prefix : String
    record StatsMsg, reply : Channel(CacheStats)
    record EnabledSetMsg, value : Bool
    record EnabledGetMsg, reply : Channel(Bool)
    record MaxSizeSetMsg, value : Int32
    record MaxSizeGetMsg, reply : Channel(Int32)
    record CleanupMsg

    def initialize(max_size : Int32 = 1000, enabled : Bool = true)
      @cmd = Channel(GetMsg | SetMsg | ClearMsg | ClearByPrefixMsg | StatsMsg | EnabledSetMsg | EnabledGetMsg | MaxSizeSetMsg | MaxSizeGetMsg | CleanupMsg).new
      @entries = {} of String => CacheEntry
      @eviction_order = Deque(String).new
      @eviction_set = Set(String).new
      @stats = CacheStats.new
      @max_size = max_size
      @enabled = enabled

      spawn { run_owner_fiber }

      PeriodicCleanup.start_periodic_cleanup(60.seconds) { cleanup }
    end

    private def run_owner_fiber
      loop do
        begin
          loop { handle_message }
        rescue ex
          ::Log.for("fetcher").error { "CacheStore owner fiber crashed: #{ex.class} - #{ex.message} (restarting)" }
          ::sleep(10.milliseconds)
        end
      end
    end

    private def handle_message
      msg = @cmd.receive
      case msg
      when GetMsg
        unless @enabled
          msg.reply.send(nil)
          return
        end

        entry = @entries[msg.key]?
        if entry.nil?
          @stats.record_miss
          msg.reply.send(nil)
        elsif entry.expired?
          remove_entry(msg.key)
          @stats.record_miss
          msg.reply.send(nil)
        else
          @stats.record_hit
          msg.reply.send(entry.value)
        end
      when SetMsg
        return unless @enabled
        if @entries[msg.key]?
          @entries[msg.key] = CacheEntry.new(msg.value, Time.utc, msg.ttl)
          @eviction_order.reject! { |k| k == msg.key }
          @eviction_set.delete(msg.key)
          @eviction_order << msg.key
          @eviction_set.add(msg.key)
        else
          evict_if_needed
          @entries[msg.key] = CacheEntry.new(msg.value, Time.utc, msg.ttl)
          @eviction_order << msg.key
          @eviction_set.add(msg.key)
        end
      when ClearMsg
        @entries.clear
        @eviction_order.clear
        @eviction_set.clear
        @stats = CacheStats.new
      when ClearByPrefixMsg
        keys_to_remove = [] of String
        @entries.each_key do |key|
          keys_to_remove << key if key.starts_with?(msg.prefix)
        end
        keys_to_remove.each do |key|
          @entries.delete(key)
          @eviction_set.delete(key)
        end
        @eviction_order.reject!(&.starts_with?(msg.prefix))
      when StatsMsg
        msg.reply.send(CacheStats.snapshot(@stats.hits, @stats.misses, @stats.evictions))
      when EnabledSetMsg
        @enabled = msg.value
      when EnabledGetMsg
        msg.reply.send(@enabled)
      when MaxSizeSetMsg
        @max_size = msg.value
      when MaxSizeGetMsg
        msg.reply.send(@max_size)
      when CleanupMsg
        BoundedRegistry.cleanup(@entries)
      end
    end

    def get(key : String) : Result?
      ch = Channel(Result?).new
      @cmd.send(GetMsg.new(key, ch))
      ch.receive
    end

    def set(key : String, value : Result, ttl : Time::Span)
      @cmd.send(SetMsg.new(key, value, ttl))
    end

    def clear
      @cmd.send(ClearMsg.new)
    end

    def clear_by_prefix(prefix : String)
      @cmd.send(ClearByPrefixMsg.new(prefix))
    end

    def stats : CacheStats
      ch = Channel(CacheStats).new
      @cmd.send(StatsMsg.new(ch))
      ch.receive
    end

    def enabled? : Bool
      ch = Channel(Bool).new
      @cmd.send(EnabledGetMsg.new(ch))
      ch.receive
    end

    def enabled=(value : Bool)
      @cmd.send(EnabledSetMsg.new(value))
    end

    def max_size : Int32
      ch = Channel(Int32).new
      @cmd.send(MaxSizeGetMsg.new(ch))
      ch.receive
    end

    def max_size=(value : Int32)
      @cmd.send(MaxSizeSetMsg.new(value))
    end

    def cleanup
      @cmd.send(CleanupMsg.new)
    end

    private def remove_entry(key : String)
      @entries.delete(key)
      @eviction_set.delete(key)
      @eviction_order.reject! { |k| k == key }
    end

    private def evict_if_needed
      while @entries.size >= @max_size && !@eviction_order.empty?
        oldest_key = @eviction_order.shift?
        if oldest_key
          @entries.delete(oldest_key)
          @eviction_set.delete(oldest_key)
          @stats.record_eviction
        end
      end
    end
  end
end
