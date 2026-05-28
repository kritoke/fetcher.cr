require "log"
require "mutex"

module Fetcher
  module PeriodicCleanup
    @@global_cleanup_lock = Mutex.new
    @@registered_cleanups = Set(Proc(Nil)).new
    @@global_cleanup_fiber : Fiber?
    @@cleanup_running : Bool = false
    @@cleanup_interval : Time::Span = 60.seconds
    @@cleanup_stopped : Bool = false

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
      @@cleanup_stopped = true
      @@cleanup_running = true

      @@global_cleanup_fiber = spawn do
        @@cleanup_stopped = false
        loop do
          if @@cleanup_stopped
            @@cleanup_running = false
            break
          end

          sleep @@cleanup_interval

          if @@cleanup_stopped
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
