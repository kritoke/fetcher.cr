require "spec"
require "../src/fetcher"

describe "RequestConfig retry settings" do
  it "has default retry values" do
    config = Fetcher::RequestConfig.new
    config.retry.max_retries.should eq(3)
    config.retry.base_delay.should eq(1.second)
    config.retry.max_delay.should eq(30.seconds)
    config.retry.exponential_base.should eq(2.0)
  end

  it "allows custom retry configuration" do
    config = Fetcher::RequestConfig.new(
      retry: Fetcher::RetryConfig.new(max_retries: 5, base_delay: 2.seconds)
    )
    config.retry.max_retries.should eq(5)
    config.retry.base_delay.should eq(2.seconds)
  end

  it "calculates exponential backoff correctly" do
    config = Fetcher::RequestConfig.new(
      retry: Fetcher::RetryConfig.new(base_delay: 10.seconds, max_delay: 30.seconds)
    )

    attempt = 2
    delay = config.retry.base_delay * (config.retry.exponential_base ** attempt)
    delay = config.retry.max_delay if delay > config.retry.max_delay

    delay.should eq(30.seconds)
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
    config = Fetcher::RequestConfig.new(
      retry: Fetcher::RetryConfig.new(base_delay: 10.seconds, max_delay: 30.seconds)
    )
    config.delay_for_attempt(1).should eq(20.seconds)
    config.delay_for_attempt(2).should eq(30.seconds)
    config.delay_for_attempt(10).should eq(30.seconds)
  end
end

describe "RequestConfig" do
  it "has configurable timeouts" do
    config = Fetcher::RequestConfig.new(
      timeout: Fetcher::TimeoutConfig.new(connect: 30.seconds, read: 60.seconds)
    )
    config.timeout.connect.should eq(30.seconds)
    config.timeout.read.should eq(60.seconds)
  end

  it "has default values" do
    config = Fetcher::RequestConfig.new
    config.timeout.connect.should eq(10.seconds)
    config.timeout.read.should eq(30.seconds)
  end
end
