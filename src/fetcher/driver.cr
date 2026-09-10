require "./entry"
require "./result"

module Fetcher
  # Process-level registry of all concrete driver classes. Populated
  # by the `inherited` macro in Driver as driver files are loaded.
  class DriverRegistry
    @@drivers = [] of Driver.class

    # Returns a snapshot (fresh duplicate) of the driver registry.
    def self.all : Array(Driver.class)
      @@drivers.dup
    end

    # Register a driver class. Called automatically by the
    # `inherited` macro when a class inherits from Driver.
    def self.register(klass : Driver.class) : Nil
      @@drivers << klass unless @@drivers.includes?(klass)
    end

    # Drop all registered drivers. Mainly useful in tests.
    def self.clear : Nil
      @@drivers.clear
    end
  end

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

    # Returns a snapshot of the driver registry — a fresh duplicate on
    # every call so callers can mutate without affecting the registry.
    # New drivers added after the first call (e.g., loaded by a
    # plugin) ARE reflected on the next call.
    def self.registry : Array(Driver.class)
      DriverRegistry.all
    end

    # Force-rebuild the registry cache. Currently a no-op since
    # `registry` returns a fresh array on every call. Retained for
    # API compatibility in case the implementation caches later.
    def self.refresh_registry : Array(Driver.class)
      registry
    end

    macro inherited
      {% unless @type.abstract? %}
        # Concrete subclass discovered — register it.
        Fetcher::DriverRegistry.register({{ @type }})
      {% end %}
    end
  end
end
