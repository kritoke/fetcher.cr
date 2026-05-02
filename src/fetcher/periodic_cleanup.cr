require "mutex"

module Fetcher
  module PeriodicCleanup
    @@global_cleanup_lock = Mutex.new
    @@registered_cleanups = [] of Proc(Nil)
    @@global_cleanup_fiber : Fiber?
    @@cleanup_running : Bool = false
    @@cleanup_interval : Time::Span = 60.seconds

    def self.start_periodic_cleanup(interval : Time::Span = 60.seconds, force : Bool = false, &cleanup)
      raise ArgumentError.new("start_periodic_cleanup requires a block") unless cleanup

      @@global_cleanup_lock.synchronize do
        @@registered_cleanups << cleanup
        @@cleanup_interval = interval

        if !@@cleanup_running || force
          restart_fiber
        end
      end

      nil
    end

    def self.register_cleanup(&cleanup : Proc(Nil)) : Nil
      @@global_cleanup_lock.synchronize do
        @@registered_cleanups << cleanup
        if !@@cleanup_running
          restart_fiber
        end
      end
    end

    private def self.restart_fiber : Nil
      @@cleanup_running = true
      @@global_cleanup_fiber = spawn do
        loop do
          sleep @@cleanup_interval
          @@global_cleanup_lock.synchronize do
            @@registered_cleanups.each(&.call)
          end
        rescue ex
          ::Log.for("fetcher").warn { "Global periodic cleanup fiber error: #{ex.class} - #{ex.message}" }
        ensure
          @@cleanup_running = false
        end
      end
    end

    def self.unregister_cleanup(&cleanup : Proc(Nil)) : Nil
      @@global_cleanup_lock.synchronize do
        @@registered_cleanups.reject! { |cleanup_item| cleanup_item == cleanup }
      end
    end

    private def self.cleanup_running? : Bool
      @@cleanup_running
    end
  end
end
