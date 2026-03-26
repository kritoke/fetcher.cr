# Configuration Centralization Specification

## ADDED Requirements

### Requirement: Centralized configuration constants
All default configuration values SHALL be defined in a single `Fetcher::Config` module.

#### Scenario: Configuration discovery
- **WHEN** developers need to understand default configuration
- **THEN** they SHALL look at `Fetcher::Config` module
- **AND** all defaults SHALL be in one location
- **AND** the defaults SHALL be well-documented with comments

### Requirement: Timeout configuration
All timeout-related defaults SHALL be centralized.

#### Scenario: Default timeouts
- **WHEN** no timeout configuration is provided
- **THEN** the system SHALL use:
  - `Config::DEFAULT_CONNECT_TIMEOUT = 10.seconds`
  - `Config::DEFAULT_READ_TIMEOUT = 30.seconds`
- **AND** these values SHALL be used consistently across all modules

### Requirement: Circuit breaker configuration
All circuit breaker defaults SHALL be centralized.

#### Scenario: Default circuit breaker settings
- **WHEN** no circuit breaker configuration is provided
- **THEN** the system SHALL use:
  - `Config::DEFAULT_CIRCUIT_BREAKER_THRESHOLD = 5`
  - `Config::DEFAULT_CIRCUIT_BREAKER_TIMEOUT = 60.seconds`
- **AND** these values SHALL be used in `RequestConfig` record

### Requirement: Rate limiter configuration
All rate limiter defaults SHALL be centralized.

#### Scenario: Default rate limiter settings
- **WHEN** no rate limiter configuration is provided
- **THEN** the system SHALL use:
  - `Config::DEFAULT_RATE_LIMIT_CAPACITY = 10.0`
  - `Config::DEFAULT_RATE_LIMIT_REFILL_RATE = 1.0` (tokens per second)
- **AND** these values SHALL be used in `RequestConfig` record

### Requirement: Feed size limits
All feed size limits SHALL be centralized.

#### Scenario: Default feed size
- **WHEN** no feed size limit is configured
- **THEN** the system SHALL use:
  - `Config::MAX_FEED_SIZE = 10 * 1024 * 1024` (10MB)
  - `Config::MAX_LIMIT = 1000`
  - `Config::DEFAULT_LIMIT = 100`
- **AND** these values SHALL be used in `SafeFeedProcessor` and all fetch methods

### Requirement: Retry configuration
All retry-related defaults SHALL be centralized.

#### Scenario: Default retry settings
- **WHEN** no retry configuration is provided
- **THEN** the system SHALL use:
  - `Config::DEFAULT_MAX_RETRIES = 3`
  - `Config::DEFAULT_RETRY_BASE_DELAY = 1.second`
  - `Config::DEFAULT_RETRY_MAX_DELAY = 30.seconds`
  - `Config::DEFAULT_RETRY_EXPONENTIAL_BASE = 2.0`
- **AND** these values SHALL be used in `RequestConfig` and `with_retry` method
