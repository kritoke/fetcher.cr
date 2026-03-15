require "time"
require "mutex"

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
    property last_failure_time : Time? = nil

    @mutex : Mutex = Mutex.new

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
          check_recovery
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
        @last_failure_time = Time.utc

        if @state == State::HalfOpen
          @state = State::Open
        elsif @failure_count >= @failure_threshold
          @state = State::Open
        end
      end
    end

    private def check_recovery : Bool
      if last_failure = @last_failure_time
        elapsed = Time.utc - last_failure
        if elapsed >= @recovery_timeout
          @state = State::HalfOpen
          return true
        end
      end
      false
    end

    module Registry
      extend self

      @@circuit_breakers = {} of String => CircuitBreaker
      @@lock = Mutex.new

      def get(domain : String, config) : CircuitBreaker
        @@lock.synchronize do
          @@circuit_breakers[domain] ||= CircuitBreaker.new(
            failure_threshold: config.circuit_breaker_failure_threshold,
            recovery_timeout: config.circuit_breaker_recovery_timeout
          )
        end
      end

      def clear : Nil
        @@lock.synchronize do
          @@circuit_breakers.clear
        end
      end

      def all_states : Hash(String, {State, Int32})
        @@lock.synchronize do
          @@circuit_breakers.transform_values { |breaker| {breaker.state, breaker.failure_count} }
        end
      end
    end
  end
end
