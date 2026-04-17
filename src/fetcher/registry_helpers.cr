require "mutex"

module Fetcher
  module RegistryHelpers
    @@cleanup_running : Bool = false

    def self.enforce_registry_limit(entries : Hash(String, T), max_entries : Int32, default_ttl : Time::Span) : Nil forall T
      return if entries.size < max_entries

      now = Time.utc
      entries.reject! do |_, entry|
        now - entry.last_accessed > default_ttl
      end

      return if entries.size < max_entries

      sorted = entries.to_a.sort_by { |_, entry| entry.last_accessed }
      excess = sorted.first(entries.size - max_entries + 100)
      excess.each { |key, _| entries.delete(key) }
    end
  end
end
