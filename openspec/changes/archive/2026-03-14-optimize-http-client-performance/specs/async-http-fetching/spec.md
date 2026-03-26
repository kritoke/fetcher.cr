## ADDED Requirements

### Requirement: Async HTTP Fetching
The system SHALL use Crystal's async/await pattern for non-blocking I/O operations and reduce fiber stack memory usage during feed fetching.

#### Scenario: Non-blocking I/O operations
- **WHEN** HTTP requests are made to fetch feeds
- **THEN** the operations use Crystal's async/await pattern
- **THEN** the system does not block fibers during I/O wait periods

#### Scenario: Reduced fiber memory usage
- **WHEN** multiple concurrent fetches are processed
- **THEN** the system reuses fiber stacks where possible
- **THEN** total memory usage is reduced compared to the previous blocking implementation

#### Scenario: Backward compatibility
- **WHEN** existing synchronous APIs are called
- **THEN** they continue to work without modification
- **THEN** internally they utilize the new async infrastructure