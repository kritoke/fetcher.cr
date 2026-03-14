require "spec"
require "../src/fetcher/adaptive_concurrency_controller"

describe Fetcher::AdaptiveConcurrencyController do
  it "should initialize with default config" do
    controller = Fetcher::AdaptiveConcurrencyController.new
    controller.max_limit.should eq 16
    controller.current_limit.should eq 16
  end

  it "should respect max_concurrent_requests configuration" do
    config = Fetcher::RequestConfig.new(max_concurrent_requests: 8)
    controller = Fetcher::AdaptiveConcurrencyController.new(config)
    controller.max_limit.should eq 8
  end

  it "should clamp max_concurrent_requests to valid range" do
    # Test upper bound
    config_high = Fetcher::RequestConfig.new(max_concurrent_requests: 200)
    controller_high = Fetcher::AdaptiveConcurrencyController.new(config_high)
    controller_high.max_limit.should eq 100

    # Test lower bound
    config_low = Fetcher::RequestConfig.new(max_concurrent_requests: 1)
    controller_low = Fetcher::AdaptiveConcurrencyController.new(config_low)
    controller_low.max_limit.should eq 2
  end
end
