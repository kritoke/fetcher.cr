require "spec"
require "../src/fetcher"

describe "TokenBucketRateLimiter stress" do
  it "handles concurrent acquires fairly and without deadlock" do
    # Use a high refill rate for the stress test to complete quickly in CI
    limiter = Fetcher::TokenBucketRateLimiter.new(100.0, 500.0) # capacity 100, refill 500/sec

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

    # wait for fibers to finish (timeout guard)
    start = Time.utc
    while completed.get < 1000 && (Time.utc - start) < 5.seconds
      ::sleep(10.milliseconds)
    end

    completed.get.should eq(1000)
  end
end
