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

      # Spawn owner fiber
      spawn do
        # periodic tick to process waiters and refill tokens
        spawn do
          loop do
            ::sleep(0.05.seconds)
            @cmd.send(TickMsg.new)
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
            end

          when AvailableTokensMsg
            refill_tokens
            msg.reply.send(@tokens)

          when TickMsg
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
