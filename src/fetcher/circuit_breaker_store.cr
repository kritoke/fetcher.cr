require "./registry_store"
require "./circuit_breaker"

module Fetcher
  class CircuitBreakerStore < RegistryStore(CircuitBreaker)
    def create_value(config) : CircuitBreaker
      CircuitBreaker.new(
        failure_threshold: config.circuit_breaker.failure_threshold,
        recovery_timeout: config.circuit_breaker.recovery_timeout
      )
    end

    def all_states : Hash(String, {CircuitBreaker::State, Int32})
      @lock.synchronize do
        @entries.transform_values { |entry| {entry.value.state, entry.value.failure_count} }
      end
    end
  end
end
