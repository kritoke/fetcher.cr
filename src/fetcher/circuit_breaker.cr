require "time"
require "mutex"

module Fetcher
  class CircuitBreaker
    enum State
      Closed
      Open
      HalfOpen
    end

    record RegistryEntry,
      breaker : CircuitBreaker,
      last_accessed : Time,
      ttl : Time::Span

    getter failure_threshold : Int32
    getter recovery_timeout : Time::Span
    getter failure_count : Int32 = 0
    getter state : State = State::Closed
    property last_failure_time : Time? = nil

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
        @last_failure_time = Time.utc

        if @state == State::HalfOpen
          @state = State::Open
        elsif @failure_count >= @failure_threshold
          @state = State::Open
        end
      end
    end

    private def recovery_timeout_elapsed? : Bool
      if last_failure = @last_failure_time
        Time.utc - last_failure >= @recovery_timeout
      else
        false
      end
    end

    module Registry
      extend self

      @@entries = {} of String => RegistryEntry
      @@lock = Mutex.new
      @@cleanup_channel = Channel(Nil).new(1)
      @@cleanup_running = false
      @@cleanup_lock = Mutex.new
      DEFAULT_TTL = 5.minutes

      def get(domain : String, config) : CircuitBreaker
        @@lock.synchronize do
          entry = @@entries[domain]?
          if entry
            @@entries[domain] = RegistryEntry.new(
              breaker: entry.breaker,
              last_accessed: Time.utc,
              ttl: entry.ttl
            )
            return entry.breaker
          end

          breaker = CircuitBreaker.new(
            failure_threshold: config.circuit_breaker.failure_threshold,
            recovery_timeout: config.circuit_breaker.recovery_timeout
          )
          entry = RegistryEntry.new(
            breaker: breaker,
            last_accessed: Time.utc,
            ttl: DEFAULT_TTL
          )
          @@entries[domain] = entry
          start_cleanup_if_needed
          breaker
        end
      end

      def clear : Nil
        @@lock.synchronize do
          @@entries.clear
        end
      end

      def all_states : Hash(String, {State, Int32})
        @@lock.synchronize do
          @@entries.transform_values { |entry| {entry.breaker.state, entry.breaker.failure_count} }
        end
      end

      def cleanup : Nil
        @@lock.synchronize do
          now = Time.utc
          @@entries.reject! do |_, entry|
            now - entry.last_accessed > entry.ttl
          end
        end
      end

      private def start_cleanup_if_needed : Nil
        @@cleanup_lock.synchronize do
          return if @@cleanup_running
          @@cleanup_running = true
        end
        spawn do
          loop do
            sleep 60.seconds
            cleanup
          end
        end
      end
    end
  end
end
