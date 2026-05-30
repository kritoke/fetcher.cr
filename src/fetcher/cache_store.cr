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
    record StopMsg

    @cleanup_proc : Proc(Nil)?
    @cleanup_registered : Bool
    @stopped : Bool = false

    def initialize(max_size : Int32 = 1000, enabled : Bool = true)
      @cmd = Channel(GetMsg | SetMsg | ClearMsg | ClearByPrefixMsg | StatsMsg | EnabledSetMsg | EnabledGetMsg | MaxSizeSetMsg | MaxSizeGetMsg | CleanupMsg).new
      @entries = {} of String => CacheEntry
      @eviction_order = Deque(String).new
      @eviction_set = Set(String).new
      @stats = CacheStats.new
      @max_size = max_size
      @enabled = enabled
      @cleanup_proc = nil
      @cleanup_registered = false

      spawn { run_owner_fiber }

      register_cleanup_once
    end

    private def cleanup_proc : Proc(Nil)
      @cleanup_proc ||= Proc(Nil).new { cleanup }
    end

    # Register this store's cleanup proc exactly once.
    private def register_cleanup_once : Nil
      return if @cleanup_registered
      @cleanup_registered = true
      PeriodicCleanup.register_cleanup { cleanup_proc.call }
    end

    private def run_owner_fiber
      loop do
        # Exit if stopped
        break if @stopped

        begin
          loop do
            # Check stopped flag between messages
            break if @stopped
            msg = @cmd.receive
            dispatch_message(msg)
            # Exit if stopped
            break if @stopped
          end
        rescue ex
          ::Log.for("fetcher").error { "CacheStore owner fiber crashed: #{ex.class} - #{ex.message} (restarting)" }
          ::sleep(10.milliseconds)
        end
      end
    rescue ex
      ::Log.for("fetcher").error { "CacheStore owner fiber terminated: #{ex.class} - #{ex.message}" }
    end

    # Gracefully stop the owner fiber and unregister cleanup.
    # Call this when RequestConfig is no longer needed.
    def close : Nil
      @cmd.send(StopMsg.new)
      unregister_cleanup
    end

    private def unregister_cleanup : Nil
      return unless @cleanup_registered && @cleanup_proc
      PeriodicCleanup.unregister_cleanup { @cleanup_proc.try(&.call) }
    end

    # Named handlers for testability
    # NOTE: The case statement dispatches to named handler methods. While it has
    # 10 branches, this is intentional — message types are stable, and each branch
    # is a simple delegation. See openspec/008 for analysis.
    private def dispatch_message(msg)
      case msg
      when GetMsg           then handle_get(msg)
      when SetMsg           then handle_set(msg)
      when ClearMsg         then handle_clear
      when ClearByPrefixMsg then handle_clear_by_prefix(msg.prefix)
      when StatsMsg         then handle_stats(msg.reply)
      when EnabledSetMsg    then handle_enabled_set(msg.value)
      when EnabledGetMsg    then handle_enabled_get(msg.reply)
      when MaxSizeSetMsg    then handle_max_size_set(msg.value)
      when MaxSizeGetMsg    then handle_max_size_get(msg.reply)
      when CleanupMsg       then handle_cleanup
      when StopMsg          then handle_stop
      end
    end

    private def handle_stop : Nil
      @stopped = true
    end
    private def handle_enabled_set(value : Bool) : Nil
      @enabled = value
    end

    private def handle_enabled_get(reply : Channel(Bool)) : Nil
      reply.send(@enabled)
    end

    private def handle_max_size_set(value : Int32) : Nil
      @max_size = value
    end

    private def handle_max_size_get(reply : Channel(Int32)) : Nil
      reply.send(@max_size)
    end

    private def handle_cleanup : Nil
      BoundedRegistry.cleanup(@entries)
    end

    private def handle_get(msg : GetMsg)
      return handle_get_disabled(msg) unless @enabled
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
    end

    private def handle_get_disabled(msg : GetMsg)
      msg.reply.send(nil)
    end

    private def handle_set(msg : SetMsg)
      return unless @enabled
      if @entries[msg.key]?
        update_entry(msg.key, msg.value, msg.ttl)
      else
        evict_if_needed
        add_entry(msg.key, msg.value, msg.ttl)
      end
    end

    private def update_entry(key : String, value : Result, ttl : Time::Span)
      @entries[key] = CacheEntry.new(value, Time.utc, ttl)
      @eviction_order.reject! { |k| k == key }
      @eviction_set.delete(key)
      @eviction_order << key
      @eviction_set.add(key)
    end

    private def add_entry(key : String, value : Result, ttl : Time::Span) : Nil
      @entries[key] = CacheEntry.new(value, Time.utc, ttl)
      # Guard against duplicate additions to preserve LRU order
      unless @eviction_set.includes?(key)
        @eviction_order << key
        @eviction_set.add(key)
      end
    end

    private def handle_clear
      @entries.clear
      @eviction_order.clear
      @eviction_set.clear
      @stats = CacheStats.new
    end

    private def handle_clear_by_prefix(prefix : String)
      @entries.each_key do |key|
        next unless key.starts_with?(prefix)
        @entries.delete(key)
        @eviction_set.delete(key)
      end
      @eviction_order.reject!(&.starts_with?(prefix))
    end

    private def handle_stats(reply : Channel(CacheStats))
      reply.send(CacheStats.snapshot(@stats.hits, @stats.misses, @stats.evictions))
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
