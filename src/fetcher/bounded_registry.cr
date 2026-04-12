require "time"

module Fetcher
  # Small helper module that encapsulates common bounded registry operations so
  # individual registries don't duplicate eviction and cleanup code.
  module BoundedRegistry
    # Ensure the provided entries hash is within size limits by evicting old items.
    def self.ensure_limit(entries : Hash(String, _), max_entries : Int32, default_ttl : Time::Span)
      RegistryHelpers.enforce_registry_limit(entries, max_entries, default_ttl)
    end

    # Remove expired entries from the provided entries hash.
    def self.cleanup(entries : Hash(String, _))
      now = Time.utc
      entries.reject! do |_, entry|
        last = entry.responds_to?(:last_accessed) ? entry.last_accessed : (entry.responds_to?(:timestamp) ? entry.timestamp : now)
        now - last > entry.ttl
      end
    end

    # Mark an entry as accessed by updating its last_accessed field. Expects the
    # entry value to respond to `last_accessed` and to be constructible via
    # a block that produces a replacement value when called with the old entry.
    # Update an entry's last_accessed timestamp to now if it supports a setter.
    # Returns true if the update was performed.
    def self.mark_access(entries : Hash(String, _), key : String) : Bool
      if entry = entries[key]?
        begin
          entry.last_accessed = Time.utc
          return true
        rescue
          # not writable
        end
      end
      false
    end
  end
end
