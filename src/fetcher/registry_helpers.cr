require "mutex"

module Fetcher
  # Small helper mixins for registries that need eviction and periodic cleanup
  module RegistryHelpers
    @@cleanup_lock : Mutex = Mutex.new
    @@cleanup_running : Bool = false

    # Enforce a max size on the provided entries Hash by evicting oldest entries.
    # entries: Hash(String, T) where values respond to last_accessed or timestamp
    def self.enforce_registry_limit(entries : Hash(String, _), max_entries : Int32, default_ttl : Time::Span)
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

    # RegistryHelpers contains eviction helpers. Periodic cleanup responsibilities
    # have been moved to PeriodicCleanup to keep responsibilities separate.
  end
end
