require "time"
require "mutex"

module Fetcher
  class TokenBucketRateLimiter
    # Messages for the owner fiber
    record TryAcquireMsg, tokens_requested : Float64, reply : Channel(Bool)
    record AcquireMsg, tokens_requested : Float64, reply : Channel(Nil)
    record AvailableTokensMsg, reply : Channel(Float64)
    record TickMsg

    MAX_WAIT_TIME = 0.1

    def initialize(@capacity : Float64, @refill_rate : Float64)
      # Owner channel and initial state
      @cmd = Channel(TryAcquireMsg | AcquireMsg | AvailableTokensMsg | TickMsg).new
      @tokens = @capacity
      @last_refill = Time.utc

      # Waiter queue: Array of Tuple(tokens_requested, reply_channel)
      @waiters = [] of Tuple(Float64, Channel(Nil))

      # Wake scheduling flag to avoid duplicate wakeups
      @wake_scheduled = false

      # Spawn owner fiber
      spawn do
        # Helper to schedule a wakeup when waiters are present and tokens are
        # insufficient. We schedule a single wakeup (set @wake_scheduled) to
        # avoid spawning many sleepers; wakeups are idempotent and harmless.
        schedule_wakeup = -> do
          if !@wake_scheduled && @waiters.size > 0 && @refill_rate > 0.0
            req, _ = @waiters.first
            refill_tokens
            tokens_needed = req - @tokens
            if tokens_needed > 0
              wait_time = tokens_needed / @refill_rate
              @wake_scheduled = true
              spawn do
                ::sleep(wait_time.seconds)
                @cmd.send(TickMsg.new)
              end
            end
          end
        end

        loop do
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
            else
              @waiters << {msg.tokens_requested, msg.reply}
              schedule_wakeup.call
            end

          when AvailableTokensMsg
            refill_tokens
            msg.reply.send(@tokens)

          when TickMsg
            # clear the scheduled flag, then refill and try to satisfy
            @wake_scheduled = false
            refill_tokens
            # satisfy waiters in FIFO order
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
            # If there remain waiters, schedule next wakeup
            schedule_wakeup.call
          end
        end
      end
    end

    def acquire(tokens : Float64 = 1.0)
      ch = Channel(Nil).new
      @cmd.send(AcquireMsg.new(tokens, ch))
      ch.receive
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
      now = Time.utc
      elapsed = now - @last_refill
      if elapsed > Time::Span.zero
        new_tokens = elapsed.total_seconds * @refill_rate
        @tokens = [@tokens + new_tokens, @capacity].min
        @last_refill = now
      end
    end
  end
end
