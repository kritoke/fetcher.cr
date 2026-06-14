require "time"
require "mutex"
require "./registry_helpers"
require "./periodic_cleanup"
require "./periodic_cleanup_handle"

module Fetcher
  # Entry record for RegistryStore. Defined at module level because
  # Crystal's nested types don't inherit outer generic parameters.
  struct RegistryStoreEntry(T)
    getter value : T
    getter last_accessed : Time::Span
    getter ttl : Time::Span

    def initialize(@value : T, @last_accessed : Time::Span, @ttl : Time::Span)
    end
  end

  # Abstract base class for stores that follow the Entry/get/cleanup/enforce_limit
  # pattern. Concrete stores implement `create_value(config) : T` and any
  # store-specific methods.
  abstract class RegistryStore(T)
    DEFAULT_TTL = 5.minutes

    @entries : Hash(String, RegistryStoreEntry(T))
    @max_entries : Int32
    @lock : Mutex
    @cleanup_handle : PeriodicCleanupHandle

    def initialize(@max_entries : Int32 = 10_000)
      @entries = {} of String => RegistryStoreEntry(T)
      @lock = Mutex.new
      @cleanup_handle = PeriodicCleanupHandle.new
    end

    def get(key : String, config) : T
      @lock.synchronize do
        entry = @entries[key]?
        if entry
          @entries[key] = RegistryStoreEntry(T).new(value: entry.value, last_accessed: Time.monotonic, ttl: entry.ttl)
          return entry.value
        end

        enforce_limit

        value = create_value(config)
        @entries[key] = RegistryStoreEntry(T).new(value: value, last_accessed: Time.monotonic, ttl: DEFAULT_TTL)
        @cleanup_handle.register { cleanup }
        value
      end
    end

    def cleanup : Nil
      @lock.synchronize { BoundedRegistry.cleanup(@entries) }
    end

    def clear : Nil
      @lock.synchronize { @entries.clear }
    end

    # Alias for cleanup (backward compatibility).
    def clear_expired : Nil
      cleanup
    end

    abstract def create_value(config) : T

    private def enforce_limit : Nil
      return if @entries.size < @max_entries
      sorted = @entries.to_a.sort_by { |_, entry| entry.last_accessed }
      excess_count = [@entries.size - @max_entries + 100, sorted.size].min
      excess_count.times do
        if entry = sorted.shift?
          oldest_key, _ = entry
          @entries.delete(oldest_key)
        end
      end
    end
  end
end
