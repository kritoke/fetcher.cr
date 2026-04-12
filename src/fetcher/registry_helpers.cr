module Fetcher
  # Small helper mixins for registries that need eviction and periodic cleanup
  module RegistryHelpers
    # Enforce a max size on the provided entries Hash by evicting oldest entries.
    # entries: Hash(String, T) where values respond to last_accessed or timestamp
    def enforce_registry_limit(entries : Hash(String, _), max_entries : Int32, default_ttl : Time::Span)
      return if entries.size < max_entries

      now = Time.utc
      # Purge expired first if possible
      entries.reject! do |_, entry|
        last = entry.responds_to?(:last_accessed) ? entry.last_accessed : (entry.responds_to?(:timestamp) ? entry.timestamp : now)
        now - last > default_ttl
      end

      return if entries.size < max_entries

      # Evict oldest by last_accessed/timestamp
      sorted = entries.to_a.sort_by do |_, entry|
        entry.responds_to?(:last_accessed) ? entry.last_accessed : (entry.responds_to?(:timestamp) ? entry.timestamp : now)
      end

      excess = sorted.first(entries.size - max_entries + 100)
      excess.each { |key, _| entries.delete(key) }
    end

    # Start a periodic cleanup fiber that calls the provided cleanup block every interval seconds.
    # Ensures only one cleanup fiber runs per including class via @@cleanup_running lock pattern.
    def start_periodic_cleanup(interval : Time::Span = 60.seconds, &cleanup)
      @@cleanup_lock ||= Mutex.new
      @@cleanup_running ||= false

      @@cleanup_lock.synchronize do
        return if @@cleanup_running
        @@cleanup_running = true
      end

      spawn do
        begin
          loop do
            sleep interval
            cleanup.call
          end
        rescue ex
          ::Log.for("fetcher").warn { "Registry cleanup fiber error: #{ex.class} - #{ex.message}" }
          @@cleanup_lock.synchronize { @@cleanup_running = false }
        end
      end
    end
  end
end
