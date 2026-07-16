require "log"
require "time"
require "./registry_helpers"

module Fetcher
  module BoundedRegistry
    def self.ensure_limit(entries : Hash(String, T), max_entries : Int32, default_ttl : Time::Span) : Nil forall T
      RegistryHelpers.enforce_registry_limit(entries, max_entries, default_ttl)
    end

    def self.cleanup(entries : Hash(String, T)) : Nil forall T
      now = Time.instant
      entries.reject! do |_, entry|
        now - entry.last_accessed > entry.ttl
      end
    end

    # Mark an entry as accessed by updating its last_accessed time.
    # Returns true if the entry exists and was updated, false otherwise.
    # Note: Works with entries that have mutable `last_accessed` property.
    def self.mark_access(entries : Hash(String, T), key : String) : Bool forall T
      if entry = entries[key]?
        begin
          entry.last_accessed = Time.instant
          true
        rescue ex
          Log.debug { "BoundedRegistry mark_access failed: #{ex.message}" }
          false
        end
      else
        false
      end
    end
  end
end
