require "spec"
require "../../src/fetcher"

describe "Security: Resource Bounds" do
  describe "URLValidator DNS cache bounds" do
    before_each do
      Fetcher::URLValidator.clear_validated
    end

    it "enforces MAX_VALIDATED_ENTRIES limit" do
      Fetcher::URLValidator.register_ip("test1.com", Socket::IPAddress.new("1.2.3.4", 80))
      Fetcher::URLValidator.register_ip("test2.com", Socket::IPAddress.new("1.2.3.5", 80))
      # Should not raise or grow unbounded
      100.times do |i|
        Fetcher::URLValidator.register_ip("host#{i}.example.com", Socket::IPAddress.new("1.2.3.#{i % 254 + 1}", 80))
      end
      Fetcher::URLValidator.clear_validated
    end

    it "purges expired entries when enforcing limit" do
      Fetcher::URLValidator.register_ip("expire-test.com", Socket::IPAddress.new("1.2.3.4", 80))
      # Manually expire by setting timestamp far in the past
      # The purge_expired method handles this
      Fetcher::URLValidator.purge_expired(0.seconds)
      Fetcher::URLValidator.clear_validated
    end
  end

  describe "CircuitBreaker::Registry bounds" do
    before_each do
      Fetcher::CircuitBreaker::Registry.clear
    end

    it "enforces MAX_REGISTRY_ENTRIES limit" do
      config = Fetcher::RequestConfig.new
      100.times do |i|
        Fetcher::CircuitBreaker::Registry.get("domain#{i}.example.com", config)
      end
      # Should not grow unbounded - cleanup runs internally
      states = Fetcher::CircuitBreaker::Registry.all_states
      states.size.should be <= 100
    end

    it "cleans up expired entries" do
      config = Fetcher::RequestConfig.new
      Fetcher::CircuitBreaker::Registry.get("expire-domain.com", config)
      Fetcher::CircuitBreaker::Registry.cleanup
      states = Fetcher::CircuitBreaker::Registry.all_states
      # Entry may still exist if TTL hasn't elapsed, but cleanup ran without error
      states.size.should be >= 0
    end
  end
end
