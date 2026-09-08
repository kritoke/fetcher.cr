require "./entry"
require "./result"

module Fetcher
  # Abstract contract for feed source drivers. Each feed source
  # (RSS, JSONFeed, YouTube, Reddit, Software) is implemented as a class
  # inheriting from Driver and exposing a class-level `pull` method
  # matching the signature below.
  #
  # Drivers register themselves automatically via Crystal's class
  # discovery (`< Driver` triggers the `inherited` macro below).
  # See `Fetcher::Driver.registry` for the full list.
  #
  # # Contract enforcement
  #
  # Crystal doesn't allow `abstract def self.X` on the metaclass, so
  # the default implementation raises `NotImplementedError`. Every
  # concrete driver MUST override `self.pull`. The class is still
  # declared `abstract class Driver` to prevent direct instantiation —
  # only subclasses that override `pull` are usable.
  abstract class Driver
    # Default `pull` raises. Subclasses MUST override.
    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      raise NotImplementedError.new("#{self} must implement Driver.pull")
    end

    # Process-level registry of all concrete driver classes. Populated
    # by the `inherited` macro as driver files are loaded. Frozen at
    # first access to prevent accidental mutation.
    @@registry = [] of Driver.class

    # Returns a snapshot of the driver registry — a fresh duplicate on
    # every call so callers can mutate without affecting the registry.
    # New drivers added after the first call (e.g., loaded by a
    # plugin) ARE reflected on the next call.
    def self.registry : Array(Driver.class)
      @@registry.dup
    end

    # Force-rebuild the registry cache. Currently a no-op since
    # `registry` returns a fresh array on every call. Retained for
    # API compatibility in case the implementation caches later.
    def self.refresh_registry : Array(Driver.class)
      registry
    end

    macro inherited
      {% unless @type.abstract? %}
        # Concrete subclass discovered — add it to the registry.
        @@registry << {{ @type }}
      {% end %}
    end
  end
end
