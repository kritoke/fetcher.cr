require "time"
require "mutex"

module Fetcher
  class TokenBucketRateLimiter
    @last_refill : Float64
    @max_waiters : Int32
    @pending_wakeup : Fiber?
    @wakeup_cancelled : Bool

    record TryAcquireMsg, tokens_requested : Float64, reply : Channel(Bool)
    record AcquireMsg, tokens_requested : Float64, reply : Channel(Nil | QueueFullError)
    record AvailableTokensMsg, reply : Channel(Float64)
    record TickMsg

    def initialize(@capacity : Float64, @refill_rate : Float64, @max_waiters : Int32 = 1000)
      @cmd = Channel(TryAcquireMsg | AcquireMsg | AvailableTokensMsg | TickMsg).new
      @tokens = @capacity
      @last_refill = now_seconds
      @waiters = [] of Tuple(Float64, Channel(Nil | QueueFullError))
      @wake_scheduled = false
      @wakeup_cancelled = false

      spawn { run_owner_fiber }
    end

    private def run_owner_fiber
      schedule_wakeup = -> { try_schedule_wakeup }
      loop do
        begin
          loop { handle_message(schedule_wakeup) }
        rescue ex
          ::Log.for("fetcher").error { "TokenBucket owner fiber crashed: #{ex.class} - #{ex.message} (restarting)" }
          ::sleep(10.milliseconds)
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
          @wakeup_cancelled = false
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
      @wakeup_cancelled = false
      fiber = spawn do
        ::sleep(wait_time.seconds)
        @cmd.send(TickMsg.new) unless @wakeup_cancelled
      end
      @pending_wakeup = fiber
    end

    private def cancel_pending_wakeup
      @pending_wakeup = nil
      @wakeup_cancelled = true
      @wake_scheduled = false
    end

    def acquire(tokens : Float64 = 1.0)
      ch = Channel(Nil | QueueFullError).new
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
      Time.monotonic.total_milliseconds / 1000.0
    end
  end
end
