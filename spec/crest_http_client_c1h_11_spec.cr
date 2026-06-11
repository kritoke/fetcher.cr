require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"

# Regression spec for fetcherc-c1h.11.
#
# `preflight_redirect_target` (formerly `transition_domain`) runs after a
# redirect is resolved but BEFORE the redirected request has been issued. Its
# only job is to fail fast when the target's circuit breaker is open. It must
# NOT call record_success on the target — recording success on a domain
# before we have actually exchanged a response with it inflates the
# circuit-breaker's success count and can mask real failures.
#
# Success recording for the target now lives in `perform_follow_redirect`,
# after the underlying Crest call returns.
describe Fetcher::CrestHttpClient do
  describe ".preflight_redirect_target (fetcherc-c1h.11)" do
    # Use a high failure threshold so the circuit stays Closed in the
    # "should not record success" test (we want to observe the success
    # path, not an early CircuitOpenError from the preflight itself).
    config = Fetcher::RequestConfig.new(
      circuit_breaker: Fetcher::CircuitBreakerConfig.new(failure_threshold: 5)
    )

    # Separate config for the "circuit open" test — threshold of 1 makes
    # a single record_failure enough to open the breaker.
    open_config = Fetcher::RequestConfig.new(
      circuit_breaker: Fetcher::CircuitBreakerConfig.new(failure_threshold: 1)
    )

    before_each do
      Fetcher::CircuitBreaker::Registry.clear
    end

    it "raises CircuitOpenError when the target's circuit breaker is open" do
      target_cb = Fetcher::CircuitBreaker::Registry.get("target.example", open_config)
      target_cb.record_failure # opens the breaker (threshold == 1)

      client = Fetcher::CrestHttpClient.new(open_config)
      expect_raises(Fetcher::CircuitOpenError) do
        client.debug_preflight_redirect_target("source.example", "target.example")
      end
    end

    it "does NOT record success on the target (regression for c1h.11)" do
      target_cb = Fetcher::CircuitBreaker::Registry.get("target.example", config)
      # Pre-load a failure so we can detect an erroneous record_success.
      target_cb.record_failure
      target_cb.failure_count.should eq 1

      client = Fetcher::CrestHttpClient.new(config)
      client.debug_preflight_redirect_target("source.example", "target.example")

      # If preflight were still calling record_success, the failure_count
      # would be reset to 0. The whole point of c1h.11 is that the target
      # has not been contacted yet at this point, so its circuit-breaker
      # state must be unchanged.
      target_cb.failure_count.should eq 1
    end

    it "does nothing when circuit breaker is disabled in config" do
      disabled_config = Fetcher::RequestConfig.new(
        circuit_breaker: Fetcher::CircuitBreakerConfig.new(enabled: false, failure_threshold: 1)
      )
      Fetcher::CircuitBreaker::Registry.clear

      # Even if a breaker for the target happens to exist and is open, the
      # preflight must short-circuit when the config disables the feature.
      target_cb = Fetcher::CircuitBreaker::Registry.get("target.example", disabled_config)
      target_cb.record_failure

      client = Fetcher::CrestHttpClient.new(disabled_config)
      client.debug_preflight_redirect_target("source.example", "target.example")
      # No raise — config disables the check entirely.
    end
  end
end
