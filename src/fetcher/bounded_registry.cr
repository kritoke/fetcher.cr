require "log"
require "time"

module Fetcher
  module BoundedRegistry
    def self.ensure_limit(entries : Hash(String, T), max_entries : Int32, default_ttl : Time::Span) : Nil forall T
      RegistryHelpers.enforce_registry_limit(entries, max_entries, default_ttl)
    end

    def self.cleanup(entries : Hash(String, T)) : Nil forall T
      now = Time.utc
      entries.reject! do |_, entry|
        now - entry.last_accessed > entry.ttl
      end
    end

    def self.mark_access(entries : Hash(String, T), key : String) : Bool forall T
      if entry = entries[key]?
        begin
          entry.last_accessed = Time.utc
          return true
        rescue ex
          Log.debug { "BoundedRegistry mark_access failed: #{ex.message}" }
        end
      end
      false
    end
  end
end
