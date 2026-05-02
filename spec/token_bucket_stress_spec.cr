require "spec"
require "../src/fetcher"

describe "TokenBucketRateLimiter stress" do
  it "handles concurrent acquires fairly and without deadlock" do
    limiter = Fetcher::TokenBucketRateLimiter.new(100.0, 500.0, max_waiters: 10000)

    completed = Atomic.new(0_u32)
    fibers = [] of Fiber

    100.times do
      fibers << spawn do
        10.times do
          limiter.acquire(1.0)
          completed.add(1)
        end
      end
    end

    start = Time.utc
    while completed.get < 1000 && (Time.utc - start) < 5.seconds
      ::sleep(10.milliseconds)
    end

    completed.get.should eq(1000)
  end

  it "respects max waiter queue limit" do
    limiter = Fetcher::TokenBucketRateLimiter.new(1.0, 0.1, max_waiters: 5)

    completed = Atomic.new(0_u32)
    failures = Atomic.new(0_u32)

    20.times do |_|
      spawn do
        begin
          limiter.acquire(1.0)
          completed.add(1)
        rescue Fetcher::QueueFullError
          failures.add(1)
        end
      end
    end

    ::sleep(5.seconds)

    failures.get.should be > 0
    completed.get.should be > 0
  end
end
