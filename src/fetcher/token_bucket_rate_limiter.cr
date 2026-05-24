require "time"
require "log"
require "mutex"
require "./exceptions"

module Fetcher
  class TokenBucketRateLimiter
    # Backoff intervals for retry on fiber crashes (in milliseconds)
    CRASH_BACKOFF_INTERVALS = [100, 500, 1000, 5000]
    DEFAULT_CRASH_BACKOFF   = 5000

    # Milliseconds per second for time conversions
    MS_PER_SECOND = 1000.0

    @last_refill : Float64
    @max_waiters : Int32
    @pending_wakeup : Fiber?
    @wakeup_generation : UInt64 = 0

    record TryAcquireMsg, tokens_requested : Float64, reply : Channel(Bool)
    record AcquireMsg, tokens_requested : Float64, reply : Channel(QueueFullError?)
    record AvailableTokensMsg, reply : Channel(Float64)
    record TickMsg

    def initialize(@capacity : Float64, @refill_rate : Float64, @max_waiters : Int32 = 1000)
      @cmd = Channel(TryAcquireMsg | AcquireMsg | AvailableTokensMsg | TickMsg).new
      @tokens = @capacity
      @last_refill = now_seconds
      @waiters = [] of Tuple(Float64, Channel(QueueFullError?))
      @wake_scheduled = false
      @wakeup_generation = 0_u64

      spawn { run_owner_fiber }
    end

    private def run_owner_fiber
      schedule_wakeup = -> { try_schedule_wakeup }
      consecutive_crashes = 0
      loop do
        begin
          loop { handle_message(schedule_wakeup) }
        rescue ex
          consecutive_crashes += 1
          # Prevent overflow - cap at max backoff index
          if consecutive_crashes >= CRASH_BACKOFF_INTERVALS.size
            consecutive_crashes = CRASH_BACKOFF_INTERVALS.size - 1
          end
          backoff_ms = CRASH_BACKOFF_INTERVALS.fetch(consecutive_crashes - 1, DEFAULT_CRASH_BACKOFF)
          ::Log.for("fetcher").error { "TokenBucket owner fiber crashed (##{consecutive_crashes}): #{ex.class} - #{ex.message} (retry in #{backoff_ms}ms)" }
          ::sleep(backoff_ms.milliseconds)
        end
      end
    end

    private def handle_message(schedule_wakeup)
      msg = @cmd.receive
      case msg
      when TryAcquireMsg
        refill_tokens
        if @tokens >= msg.tokens_requested
          @tokens -= msg.tokens_requested
          msg.reply.send(true)
        else
          msg.reply.send(false)
        end
      when AcquireMsg
        refill_tokens
        if @tokens >= msg.tokens_requested
          @tokens -= msg.tokens_requested
          msg.reply.send(nil)
        elsif @max_waiters > 0 && @waiters.size >= @max_waiters
          msg.reply.send(QueueFullError.new)
        else
          @waiters << {msg.tokens_requested, msg.reply}
          schedule_wakeup.call
        end
      when AvailableTokensMsg
        refill_tokens
        msg.reply.send(@tokens)
      when TickMsg
        cancel_pending_wakeup
        refill_tokens
        while @waiters.size > 0 && @tokens > 0
          req, ch = @waiters.first
          if @tokens >= req
            @tokens -= req
            @waiters.shift
            ch.send(nil)
          else
            break
          end
        end
        if @waiters.empty?
          cancel_pending_wakeup
        else
          schedule_wakeup.call
        end
      end
    end

    private def try_schedule_wakeup
      return if @wake_scheduled || @waiters.empty? || @refill_rate <= 0.0
      req, _ = @waiters.first
      refill_tokens
      tokens_needed = req - @tokens
      return unless tokens_needed > 0
      wait_time = tokens_needed / @refill_rate
      @wake_scheduled = true
      current_generation = @wakeup_generation
      fiber = spawn do
        ::sleep(wait_time.seconds)
        # Only send tick if we're still the current generation
        @cmd.send(TickMsg.new) if @wakeup_generation == current_generation
      ensure
        @wake_scheduled = false
      end
      @pending_wakeup = fiber
    end

    private def cancel_pending_wakeup
      @pending_wakeup = nil
      @wakeup_generation += 1  # Invalidate any pending wakeups
      @wake_scheduled = false
    end

    def acquire(tokens : Float64 = 1.0)
      ch = Channel(QueueFullError?).new
      @cmd.send(AcquireMsg.new(tokens, ch))
      result = ch.receive
      if result.is_a?(QueueFullError)
        raise result
      end
    end

    def try_acquire(tokens : Float64 = 1.0) : Bool
      ch = Channel(Bool).new
      @cmd.send(TryAcquireMsg.new(tokens, ch))
      ch.receive
    end

    def available_tokens : Float64
      ch = Channel(Float64).new
      @cmd.send(AvailableTokensMsg.new(ch))
      ch.receive
    end

    private def refill_tokens
      now = now_seconds
      elapsed = now - @last_refill
      if elapsed > 0.0
        # elapsed is in seconds (Float64), multiply by refill_rate
        new_tokens = elapsed * @refill_rate
        @tokens = [@tokens + new_tokens, @capacity].min
        @last_refill = now
      end
    end

    private def now_seconds : Float64
      Time.monotonic.total_milliseconds / MS_PER_SECOND
    end
  end
end
