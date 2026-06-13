module Fetcher
  # One-shot PeriodicCleanup registration handle. Stores a cleanup proc
  # and ensures it's registered exactly once. Provides unregister for
  # graceful shutdown.
  #
  # Eliminates the repeated @cleanup_proc / @cleanup_registered /
  # register_cleanup_once pattern across store classes.
  class PeriodicCleanupHandle
    @proc : Proc(Nil)? = nil
    @registered : Bool = false

    # Register a cleanup proc exactly once. No-op if already registered.
    # Thread-safe: PeriodicCleanup.register_cleanup handles its own locking.
    def register(&block : -> Nil)
      return if @registered
      @registered = true
      @proc = block
      PeriodicCleanup.register_cleanup { block.call }
    end

    # Unregister the cleanup proc. No-op if not registered.
    # Used for graceful shutdown (e.g., CacheStore.close).
    def unregister
      return unless @registered && @proc
      PeriodicCleanup.unregister_cleanup { @proc.try(&.call) }
      @registered = false
    end
  end
end
