require "log"
require "mutex"

module Fetcher
  module PeriodicCleanup
    @@global_cleanup_lock = Mutex.new
    @@registered_cleanups = Set(Proc(Nil)).new
    # The running fiber paired with its own stop channel. The channel is
    # closure-captured by the fiber, so the global is only used to signal
    # shutdown to the *current* fiber on restart (close the channel, the
    # fiber's `select` unblocks, the loop exits).
    @@global_cleanup : Tuple(Fiber, Channel(Bool))?
    @@cleanup_running : Bool = false
    @@cleanup_interval : Time::Span = 60.seconds

    def self.start_periodic_cleanup(interval : Time::Span = 60.seconds, force : Bool = false, &cleanup : Proc(Nil))
      raise ArgumentError.new("start_periodic_cleanup requires a block") unless cleanup

      @@global_cleanup_lock.synchronize do
        @@registered_cleanups.add(cleanup)
        @@cleanup_interval = interval

        if !@@cleanup_running || force
          restart_fiber
        end
      end

      nil
    end

    def self.register_cleanup(&cleanup : Proc(Nil)) : Nil
      @@global_cleanup_lock.synchronize do
        @@registered_cleanups.add(cleanup)
        if !@@cleanup_running
          restart_fiber
        end
      end
    end

    private def self.restart_fiber : Nil
      # Signal the previous fiber to exit by closing its stop channel.
      # This must happen *before* we spawn the new fiber so the old one
      # releases its reference to the (now-stale) @@registered_cleanups.
      previous = @@global_cleanup
      if previous
        _old_fiber, old_stop = previous
        old_stop.close
      end

      stop = Channel(Bool).new
      @@cleanup_running = true

      @@global_cleanup = {spawn do
        loop do
          # Wait for stop signal or interval
          select
          when stop.receive
            # Stopped by restart_fiber
            break
          when timeout @@cleanup_interval
            # Interval elapsed, run cleanup
          end

          # Check if stopped
          if stop.closed?
            @@cleanup_running = false
            break
          end

          @@global_cleanup_lock.synchronize do
            @@registered_cleanups.each do |cleanup|
              begin
                cleanup.call
              rescue ex
                ::Log.for("fetcher").error { "PeriodicCleanup task failed: #{ex.class} - #{ex.message}" }
              end
            end
          end
        end
      rescue ex
        ::Log.for("fetcher").error { "Global periodic cleanup fiber crashed: #{ex.class} - #{ex.message}" }
        @@cleanup_running = false
      end, stop}
    end

    def self.unregister_cleanup(&cleanup : Proc(Nil)) : Nil
      @@global_cleanup_lock.synchronize do
        @@registered_cleanups.delete(cleanup)
      end
    end

    private def self.cleanup_running? : Bool
      @@cleanup_running
    end
  end
end
