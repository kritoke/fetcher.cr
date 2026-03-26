## ADDED Requirements

### Requirement: Circuit breaker tracks per-domain failures
The system SHALL maintain a separate circuit breaker for each unique domain, tracking failure counts independently.

#### Scenario: Separate tracking for different domains
- **WHEN** domain A has 5 consecutive failures and domain B has 0 failures
- **THEN** circuit breaker for domain A opens while domain B remains closed

#### Scenario: Domain extraction from URL
- **WHEN** a request is made to "https://example.com/feed.xml"
- **THEN** the circuit breaker is tracked under domain "example.com"

### Requirement: Circuit breaker opens after failure threshold
The system SHALL open the circuit breaker when consecutive failures reach the configured threshold, rejecting subsequent requests without attempting HTTP calls.

#### Scenario: Circuit opens at threshold
- **GIVEN** failure threshold is 5
- **WHEN** 5 consecutive requests to a domain fail
- **THEN** circuit breaker opens and subsequent requests are rejected immediately

#### Scenario: Success resets failure count
- **GIVEN** circuit breaker has recorded 3 failures
- **WHEN** a request succeeds
- **THEN** failure count resets to 0 and circuit remains closed

### Requirement: Circuit breaker enters half-open state after cooldown
The system SHALL transition from open to half-open state after the configured cooldown period, allowing a single test request to determine if the service has recovered.

#### Scenario: Half-open after cooldown
- **GIVEN** circuit breaker is open with 30 second cooldown
- **WHEN** 30 seconds have elapsed since last failure
- **THEN** circuit breaker enters half-open state

#### Scenario: Half-open allows one test request
- **GIVEN** circuit breaker is in half-open state
- **WHEN** a request is made
- **THEN** request is allowed through
- **AND** if successful, circuit closes
- **AND** if failed, circuit opens again with reset cooldown

### Requirement: Circuit breaker returns appropriate error when open
The system SHALL return a structured error when a request is rejected due to an open circuit breaker.

#### Scenario: Open circuit returns error
- **GIVEN** circuit breaker is open for domain "failing.example.com"
- **WHEN** a fetch request is made to that domain
- **THEN** result contains error with kind `ErrorKind::RateLimited` or similar
- **AND** error message indicates circuit breaker is open

### Requirement: Circuit breaker is configurable
The system SHALL allow configuration of circuit breaker behavior via `RequestConfig`.

#### Scenario: Custom failure threshold
- **GIVEN** `RequestConfig` with `circuit_breaker_failure_threshold: 10`
- **WHEN** circuit breaker is created
- **THEN** it opens after 10 consecutive failures instead of default 5

#### Scenario: Custom cooldown period
- **GIVEN** `RequestConfig` with `circuit_breaker_cooldown: 60.seconds`
- **WHEN** circuit breaker opens
- **THEN** it transitions to half-open after 60 seconds

#### Scenario: Circuit breaker can be disabled
- **GIVEN** `RequestConfig` with `circuit_breaker_enabled: false`
- **WHEN** requests are made
- **THEN** no circuit breaker checking occurs and all requests proceed normally

### Requirement: Circuit breaker integrates with existing HTTP client
The system SHALL check circuit breaker state before making HTTP requests in `CrestHttpClient`.

#### Scenario: Circuit check before request
- **GIVEN** circuit breaker is open for a domain
- **WHEN** `CrestHttpClient.get` is called for that domain
- **THEN** no HTTP request is made
- **AND** error is returned immediately
