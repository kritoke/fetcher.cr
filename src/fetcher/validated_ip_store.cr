require "time"
require "mutex"
require "./registry_helpers"

module Fetcher
  # Encapsulates the validated IP cache used for DNS rebinding mitigation.
  # Keeps mutation localized behind a Mutex and provides a small API used by
  # Fetcher::URLValidator. This lets URLValidator remain a facade while the
  # cache implementation is easier to replace (actor, external store, etc.).
  class ValidatedIpStore
    # Internal entry record
    record Entry,
      ip : Socket::IPAddress,
      timestamp : Time

    def initialize(@max_entries : Int32 = 50_000, @ttl : Time::Span = 5.seconds)
      @map = {} of String => Entry
      @mutex = Mutex.new
    end

    # Register a host -> ip mapping with current timestamp.
    def register(host : String, ip : Socket::IPAddress) : Nil
      @mutex.synchronize do
        enforce_limit
        @map[host] = Entry.new(ip, Time.utc)
      end
    end

    # Purge expired entries older than provided expiry (or the store's ttl).
    def purge_expired(expiry : Time::Span? = nil) : Nil
      ttl = expiry || @ttl
      now = Time.utc
      @mutex.synchronize do
        @map.reject! { |_, entry| (now - entry.timestamp) > ttl }
      end
    end

    # Check for rebinding. Returns:
    # - true/false if there was a recent entry for this host (entry.ip == current_ip);
    # - nil if no recent entry existed (caller may then perform additional checks).
    def check_rebinding(host : String, current_ip : Socket::IPAddress) : Bool?
      @mutex.synchronize do
        if entry = @map[host]?
          if (Time.utc - entry.timestamp) <= @ttl
            return entry.ip == current_ip
          else
            @map.delete(host)
          end
        end
      end
      nil
    end

    # Clear entire store.
    def clear : Nil
      @mutex.synchronize do
        @map.clear
      end
    end

    private def enforce_limit : Nil
      return if @map.size < @max_entries
      RegistryHelpers.enforce_registry_limit(@map, @max_entries, @ttl)
    end
  end
end
