require "spec"
require "../src/fetcher/circuit_breaker"
require "../src/fetcher/request_config"

describe Fetcher::CircuitBreaker do
  describe "#initialize" do
    it "starts in Closed state" do
      cb = Fetcher::CircuitBreaker.new
      cb.state.should eq Fetcher::CircuitBreaker::State::Closed
    end

    it "accepts custom failure threshold" do
      cb = Fetcher::CircuitBreaker.new(failure_threshold: 3)
      cb.failure_threshold.should eq 3
    end

    it "accepts custom recovery timeout" do
      cb = Fetcher::CircuitBreaker.new(recovery_timeout: 30.seconds)
      cb.recovery_timeout.should eq 30.seconds
    end
  end

  describe "#record_success" do
    it "resets failure count in Closed state" do
      cb = Fetcher::CircuitBreaker.new(failure_threshold: 3)
      cb.record_failure
      cb.record_failure
      cb.failure_count.should eq 2
      
      cb.record_success
      cb.failure_count.should eq 0
    end

    it "closes circuit from HalfOpen state" do
      cb = Fetcher::CircuitBreaker.new(failure_threshold: 1, recovery_timeout: 1.second)
      cb.record_failure
      cb.state.should eq Fetcher::CircuitBreaker::State::Open
      
      cb.last_failure_time = Time.utc - 2.seconds
      cb.allow_request?.should be_true
      cb.state.should eq Fetcher::CircuitBreaker::State::HalfOpen
      
      cb.record_success
      cb.state.should eq Fetcher::CircuitBreaker::State::Closed
    end
  end

  describe "#record_failure" do
    it "increments failure count" do
      cb = Fetcher::CircuitBreaker.new
      cb.record_failure
      cb.failure_count.should eq 1
    end

    it "opens circuit when threshold reached" do
      cb = Fetcher::CircuitBreaker.new(failure_threshold: 2)
      cb.record_failure
      cb.state.should eq Fetcher::CircuitBreaker::State::Closed
      
      cb.record_failure
      cb.state.should eq Fetcher::CircuitBreaker::State::Open
    end

    it "reopens circuit from HalfOpen on failure" do
      cb = Fetcher::CircuitBreaker.new(failure_threshold: 1, recovery_timeout: 1.second)
      cb.record_failure
      cb.state.should eq Fetcher::CircuitBreaker::State::Open
      
      cb.last_failure_time = Time.utc - 2.seconds
      cb.allow_request?.should be_true
      cb.state.should eq Fetcher::CircuitBreaker::State::HalfOpen
      
      cb.record_failure
      cb.state.should eq Fetcher::CircuitBreaker::State::Open
    end
  end

  describe "#allow_request?" do
    it "returns true in Closed state" do
      cb = Fetcher::CircuitBreaker.new
      cb.allow_request?.should be_true
    end

    it "returns false in Open state before recovery timeout" do
      cb = Fetcher::CircuitBreaker.new(failure_threshold: 1, recovery_timeout: 60.seconds)
      cb.record_failure
      cb.state.should eq Fetcher::CircuitBreaker::State::Open
      
      cb.allow_request?.should be_false
    end

    it "transitions to HalfOpen after recovery timeout" do
      cb = Fetcher::CircuitBreaker.new(failure_threshold: 1, recovery_timeout: 1.second)
      cb.record_failure
      cb.state.should eq Fetcher::CircuitBreaker::State::Open
      
      cb.last_failure_time = Time.utc - 2.seconds
      cb.allow_request?.should be_true
      cb.state.should eq Fetcher::CircuitBreaker::State::HalfOpen
    end

    it "returns true in HalfOpen state" do
      cb = Fetcher::CircuitBreaker.new(failure_threshold: 1, recovery_timeout: 1.second)
      cb.record_failure
      cb.last_failure_time = Time.utc - 2.seconds
      
      cb.allow_request?.should be_true
    end
  end
end

describe Fetcher::CircuitBreaker::Registry do
  before_each do
    Fetcher::CircuitBreaker::Registry.clear
  end

  describe ".get" do
    it "returns same circuit breaker for same domain" do
      config = Fetcher::RequestConfig.new
      cb1 = Fetcher::CircuitBreaker::Registry.get("example.com", config)
      cb2 = Fetcher::CircuitBreaker::Registry.get("example.com", config)
      
      cb1.should be(cb2)
    end

    it "returns different circuit breakers for different domains" do
      config = Fetcher::RequestConfig.new
      cb1 = Fetcher::CircuitBreaker::Registry.get("example.com", config)
      cb2 = Fetcher::CircuitBreaker::Registry.get("other.com", config)
      
      cb1.should_not be(cb2)
    end

    it "uses config settings for new circuit breaker" do
      config = Fetcher::RequestConfig.new(
        circuit_breaker_failure_threshold: 10,
        circuit_breaker_recovery_timeout: 120.seconds
      )
      cb = Fetcher::CircuitBreaker::Registry.get("example.com", config)
      
      cb.failure_threshold.should eq 10
      cb.recovery_timeout.should eq 120.seconds
    end
  end

  describe ".clear" do
    it "removes all circuit breakers" do
      config = Fetcher::RequestConfig.new
      Fetcher::CircuitBreaker::Registry.get("example.com", config)
      Fetcher::CircuitBreaker::Registry.get("other.com", config)
      
      Fetcher::CircuitBreaker::Registry.clear
      
      Fetcher::CircuitBreaker::Registry.all_states.empty?.should be_true
    end
  end

  describe ".all_states" do
    it "returns states for all domains" do
      config = Fetcher::RequestConfig.new(circuit_breaker_failure_threshold: 1)
      
      cb = Fetcher::CircuitBreaker::Registry.get("failing.com", config)
      cb.record_failure
      
      states = Fetcher::CircuitBreaker::Registry.all_states
      states.has_key?("failing.com").should be_true
      states["failing.com"][0].should eq Fetcher::CircuitBreaker::State::Open
    end
  end
end
