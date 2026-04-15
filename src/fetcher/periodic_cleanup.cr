require "mutex"

module Fetcher
  # Shared helper to start a single periodic cleanup fiber per including class.
  module PeriodicCleanup
    # Track running cleanup tasks keyed by the cleanup Proc's object id. This
    # lets multiple independent owners register their own periodic cleanup
    # fibers without interfering with each other while preserving the
    # start_periodic_cleanup API (non-breaking).
    @@tasks_lock : Mutex = Mutex.new
    @@tasks = {} of UInt64 => Bool

    # Start a periodic cleanup fiber that calls the provided cleanup block every `interval`.
    # If the same cleanup block (by identity) is already running this method
    # is a no-op unless `force` is true. This preserves the previous
    # "only one cleanup" behavior at the per-task level rather than globally.
    def self.start_periodic_cleanup(interval : Time::Span = 60.seconds, force : Bool = false, &cleanup)
      raise ArgumentError.new("start_periodic_cleanup requires a block") unless cleanup

      # Use the cleanup Proc's hash as a stable key to identify distinct blocks.
      key = cleanup.hash

      @@tasks_lock.synchronize do
        running = @@tasks[key]? || false
        return if running && !force
        @@tasks[key] = true
      end

      spawn do
        begin
          loop do
            sleep interval
            cleanup.call
          end
        rescue ex
          ::Log.for("fetcher").warn { "Periodic cleanup fiber error: #{ex.class} - #{ex.message}" }
          @@tasks_lock.synchronize { @@tasks[key] = false }
        end
      end
    end
  end
end
