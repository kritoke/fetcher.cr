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
      last_accessed : Time::Instant

    getter max_entries : Int32

    def initialize(@max_entries : Int32 = 10_000, @ttl : Time::Span = 5.seconds)
      @map = {} of String => Entry
      @mutex = Mutex.new
      @drain_threshold = (@max_entries * 0.8).to_i32

      # NOTE: The short TTL (5 seconds default) creates a trade-off between:
      # - Security: Short TTL reduces window for DNS rebinding attacks
      # - Performance: Short TTL means more frequent re-validation
      # For high-security environments, consider a longer TTL combined with IP allowlisting.
    end

    # Register a host -> ip mapping with current timestamp.
    def register(host : String, ip : Socket::IPAddress) : Nil
      @mutex.synchronize do
        register_internal(host, ip)
      end
    end

    private def register_internal(host : String, ip : Socket::IPAddress) : Nil
      drain_if_needed
      enforce_limit
      @map[host] = Entry.new(ip, Time.instant)
    end

    # Drains stale entries when MAP approaches capacity. Safe to call frequently;
    # is a no-op below the drain threshold (80% of max).
    private def drain_if_needed : Nil
      return if @map.size < @drain_threshold
      purge_expired
    end

    private def enforce_limit : Nil
      return if @map.size < @max_entries
      RegistryHelpers.enforce_registry_limit(@map, @max_entries, @ttl)
    end

    # Purge expired entries older than provided expiry (or the store's ttl).
    # Called implicitly by `register` when approaching max capacity (80%).
    def purge_expired(expiry : Time::Span? = nil) : Nil
      ttl = expiry || @ttl
      now = Time.instant
      @mutex.synchronize do
        @map.reject! { |_, entry| (now - entry.last_accessed) > ttl }
      end
    end

    # Check for rebinding. Returns:
    # - true/false if there was a recent entry for this host (entry.ip == current_ip);
    # - nil if no recent entry existed (caller may then perform additional checks).
    def check_rebinding(host : String, current_ip : Socket::IPAddress) : Bool?
      @mutex.synchronize do
        if entry = @map[host]?
          if (Time.instant - entry.last_accessed) <= @ttl
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
  end
end
