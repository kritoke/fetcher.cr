## ADDED Requirements

### Requirement: HTTP Client Connection Pooling
The system SHALL implement a shared HTTP client connection pool with configurable size that reuses connections across multiple fetch operations.

#### Scenario: Connection reuse within same domain
- **WHEN** multiple feeds from the same domain are fetched concurrently
- **THEN** the system reuses existing HTTP connections from the pool

#### Scenario: Configurable pool size
- **WHEN** the feeds.yml configuration includes http_client_pool_size setting
- **THEN** the connection pool uses the specified size
- **WHEN** no configuration is provided
- **THEN** the system uses a default pool size of 10

#### Scenario: Connection lifecycle management
- **WHEN** connections in the pool become stale or invalid
- **THEN** the system automatically removes and replaces them