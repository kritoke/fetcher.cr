require "mutex"

module Fetcher
  # Shared helper to start a single periodic cleanup fiber per including class.
  module PeriodicCleanup
    @@cleanup_lock : Mutex = Mutex.new
    @@cleanup_running : Bool = false

    # Start a periodic cleanup fiber that calls the provided cleanup block every `interval`.
    # Ensures only one cleanup fiber runs for the process using a class-level flag.
    def self.start_periodic_cleanup(interval : Time::Span = 60.seconds, force : Bool = false, &cleanup)
      @@cleanup_lock ||= Mutex.new
      @@cleanup_running ||= false

      @@cleanup_lock.synchronize do
        return if @@cleanup_running && !force
        @@cleanup_running = true
      end

      spawn do
        begin
          loop do
            sleep interval
            cleanup.call
          end
        rescue ex
          ::Log.for("fetcher").warn { "Periodic cleanup fiber error: #{ex.class} - #{ex.message}" }
          @@cleanup_lock.synchronize { @@cleanup_running = false }
        end
      end
    end
  end
end
