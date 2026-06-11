require "time"
require "mutex"
require "./registry_helpers"
require "./periodic_cleanup"
require "./circuit_breaker_store"

module Fetcher
  class CircuitBreaker
    enum State
      Closed
      Open
      HalfOpen
    end

    getter failure_threshold : Int32
    getter recovery_timeout : Time::Span
    getter failure_count : Int32 = 0
    getter state : State = State::Closed
    # Time::Span from Time.monotonic -- a monotonic counter that's safe
    # against NTP/suspend jumps. Wall-clock (Time.utc) would miscalculate
    # the recovery window if the system clock jumped.
    property last_failure_time : Time::Span? = nil

    @mutex : Mutex = Mutex.new

    DEFAULT_TTL = 5.minutes

    def initialize(
      @failure_threshold : Int32 = 5,
      @recovery_timeout : Time::Span = 60.seconds,
    )
    end

    def allow_request? : Bool
      @mutex.synchronize do
        case @state
        in State::Closed
          true
        in State::Open
          if recovery_timeout_elapsed?
            @state = State::HalfOpen
            @last_failure_time = Time.monotonic  # Reset for correct timeout calculation
            true
          else
            false
          end
        in State::HalfOpen
          true
        end
      end
    end

    def record_success : Nil
      @mutex.synchronize do
        @failure_count = 0
        @state = State::Closed
      end
    end

    def record_failure : Nil
      @mutex.synchronize do
        @failure_count += 1
        @last_failure_time = Time.monotonic

        if @state == State::HalfOpen
          @state = State::Open
        elsif @failure_count >= @failure_threshold
          @state = State::Open
        end
      end
    end

    private def recovery_timeout_elapsed? : Bool
      if last_failure = @last_failure_time
        Time.monotonic - last_failure >= @recovery_timeout
      else
        false
      end
    end

    module Registry
      extend self

      # Backwards-compatible facade that delegates to CircuitBreakerStore. This
      # localizes mutation in the store while keeping the Registry API intact.
      def get(domain : String, config) : CircuitBreaker
        store.get(domain, config)
      end

      def clear : Nil
        store.clear
      end

      def all_states : Hash(String, {State, Int32})
        store.all_states
      end

      def cleanup : Nil
        store.cleanup
      end

      def store : CircuitBreakerStore
        @@store_lock.synchronize { @@store ||= CircuitBreakerStore.new }
      end

      @@store : CircuitBreakerStore? = nil
      @@store_lock = Mutex.new
    end
  end
end
