require "spec"
require "../src/fetcher/token_bucket_rate_limiter"

describe Fetcher::TokenBucketRateLimiter do
  it "allows burst requests up to capacity" do
    # Create a limiter with capacity 5, refill rate 1 token/second
    limiter = Fetcher::TokenBucketRateLimiter.new(5.0, 1.0)

    # Should allow 5 requests immediately
    5.times do
      limiter.try_acquire.should be_true
    end

    # Sixth request should fail
    limiter.try_acquire.should be_false
  end

  it "refills tokens over time" do
    limiter = Fetcher::TokenBucketRateLimiter.new(2.0, 2.0) # refill 2 tokens per second

    # Drain all tokens
    limiter.acquire(2.0)

    # Wait 0.6 seconds - should refill ~1.2 tokens
    sleep(600.milliseconds)

    # Should be able to acquire 1 token
    limiter.try_acquire(1.0).should be_true

    # Should not be able to acquire 2 tokens (only ~1.2 available)
    limiter.try_acquire(2.0).should be_false
  end

  it "respects maximum capacity" do
    limiter = Fetcher::TokenBucketRateLimiter.new(3.0, 1.0)

    # Start with 3 tokens
    limiter.available_tokens.should eq(3.0)

    # Wait 100ms - should still have only 3 tokens (capacity limit)
    sleep(100.milliseconds)
    limiter.available_tokens.should be <= 3.0
  end

  it "handles fractional tokens" do
    limiter = Fetcher::TokenBucketRateLimiter.new(1.0, 0.5) # refill 0.5 tokens per second

    # Acquire 1 token (drain bucket)
    limiter.acquire(1.0)

    # Wait 300ms - should refill 0.15 tokens
    sleep(300.milliseconds)

    # Should not be able to acquire 1 token yet (only ~0.15 available)
    limiter.try_acquire(1.0).should be_false

    # Wait longer to get more tokens
    sleep(1700.milliseconds) # Total 2 seconds = 1.0 tokens refilled
    limiter.try_acquire(1.0).should be_true
  end

  it "is thread-safe" do
    limiter = Fetcher::TokenBucketRateLimiter.new(5.0, 2.0)

    # Use a channel to collect results from fibers
    channel = Channel(Nil).new
    successful_count = 0

    # Create multiple fibers trying to acquire tokens
    10.times do
      spawn do
        if limiter.try_acquire
          successful_count += 1
        end
        channel.send(nil)
      end
    end

    # Wait for all fibers to complete
    10.times { channel.receive }

    # Should have exactly 5 successful acquisitions
    successful_count.should eq(5)
  end

  it "acquire method eventually succeeds when tokens become available" do
    limiter = Fetcher::TokenBucketRateLimiter.new(1.0, 2.0) # refill 2 tokens per second

    # Acquire the only token
    limiter.acquire(1.0)

    # Start a fiber that will try to acquire (should block initially)
    channel = Channel(Bool).new
    spawn do
      start_time = Time.utc
      limiter.acquire(1.0) # This should block until tokens are refilled
      elapsed = (Time.utc - start_time).total_seconds
      channel.send(elapsed > 0.01) # Should have waited at least a little
    end

    # Wait a bit for the fiber to potentially complete
    result = channel.receive
    result.should be_true
  end
end
