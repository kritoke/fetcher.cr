require "log"
require "mutex"

module Fetcher
  module PeriodicCleanup
    @@global_cleanup_lock = Mutex.new
    @@registered_cleanups = Set(Proc(Nil)).new
    @@global_cleanup_fiber : Fiber?
    @@cleanup_running : Bool = false
    @@cleanup_interval : Time::Span = 60.seconds
    # Channel used to signal the fiber to stop. New fibers get a new channel.
    @@stop_channel : Channel(Bool)?

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
      # Create new stop channel to signal the old fiber
      stop = Channel(Bool).new
      @@stop_channel = stop
      @@cleanup_running = true

      old_fiber = @@global_cleanup_fiber
      @@global_cleanup_fiber = spawn do
        loop do
          # Wait for stop signal or interval
          selected = select
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
      end

      # Close old stop channel to signal old fiber to stop
      # (handled by replacing @@stop_channel with new channel above)
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
