require "spec"
require "../src/fetcher"

describe "RequestConfig retry settings" do
  it "has default retry values" do
    config = Fetcher::RequestConfig.new
    config.max_retries.should eq(3)
    config.base_delay.should eq(1.second)
    config.max_delay.should eq(30.seconds)
    config.exponential_base.should eq(2.0)
  end

  it "allows custom retry configuration" do
    config = Fetcher::RequestConfig.new(max_retries: 5, base_delay: 2.seconds)
    config.max_retries.should eq(5)
    config.base_delay.should eq(2.seconds)
  end

  it "calculates exponential backoff correctly" do
    config = Fetcher::RequestConfig.new(base_delay: 10.seconds, max_delay: 30.seconds)

    # Test delay calculation (simulated)
    attempt = 2
    delay = config.base_delay * (config.exponential_base ** attempt)
    delay = config.max_delay if delay > config.max_delay

    delay.should eq(30.seconds) # 10 * 2^2 = 40, but capped at max_delay 30
  end
end

describe "RetryConfig" do
  it "calculates delay for attempts" do
    config = Fetcher::RequestConfig.new
    config.delay_for_attempt(0).should eq(1.second)
    config.delay_for_attempt(1).should eq(2.seconds)
    config.delay_for_attempt(2).should eq(4.seconds)
  end

  it "caps delay at max_delay" do
    config = Fetcher::RequestConfig.new(base_delay: 10.seconds, max_delay: 30.seconds)
    config.delay_for_attempt(1).should eq(20.seconds)
    config.delay_for_attempt(2).should eq(30.seconds)
    config.delay_for_attempt(10).should eq(30.seconds)
  end
end

describe "RequestConfig" do
  it "has configurable timeouts" do
    config = Fetcher::RequestConfig.new(
      connect_timeout: 30.seconds,
      read_timeout: 60.seconds
    )
    config.connect_timeout.should eq(30.seconds)
    config.read_timeout.should eq(60.seconds)
  end

  it "has default values" do
    config = Fetcher::RequestConfig.new
    config.connect_timeout.should eq(10.seconds)
    config.read_timeout.should eq(30.seconds)
  end
end

describe "Token Bucket Rate Limiting" do
  it "maintains backward compatibility with existing API" do
    # Test without custom rate limiting config
    result = Fetcher.pull("https://httpbin.org/get")
    result.success?.should be_true
  end

  it "allows rapid requests within burst capacity" do
    # Create a config with generous burst capacity
    config = Fetcher::RequestConfig.new(
      rate_limit_capacity: 5.0,
      rate_limit_refill_rate: 2.0
    )

    # Should be able to make 3 rapid requests
    start_time = Time.utc
    3.times do
      result = Fetcher.pull("https://httpbin.org/get", ::HTTP::Headers.new, 1, config)
      result.success?.should be_true
    end
    elapsed = Time.utc - start_time

    # Should complete quickly (under 5 seconds for network requests)
    elapsed.total_seconds.should be < 5.0
  end
end
