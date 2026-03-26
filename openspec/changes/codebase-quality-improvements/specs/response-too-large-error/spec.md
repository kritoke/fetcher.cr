# Response Too Large Error Specification

## ADDED Requirements

### Requirement: Dedicated exception type
The system SHALL define a `ResponseTooLargeError` exception for HTTP responses that exceed configured size limits.

#### Scenario: Response exceeds size limit
- **WHEN** an HTTP response body exceeds `Config::MAX_FEED_SIZE`
- **THEN** the system SHALL raise `ResponseTooLargeError`
- **AND** the error message SHALL include the actual size and the limit (e.g., "Response too large (>10MB)")
- **AND** the exception SHALL be distinct from `DNSError` to maintain semantic clarity

### Requirement: Exception hierarchy
The `ResponseTooLargeError` SHALL inherit from `FetchError` to maintain consistency with the existing error hierarchy.

#### Scenario: Exception type checking
- **WHEN** catching `ResponseTooLargeError`
- **THEN** it SHALL be catchable by `rescue FetchError` blocks
- **AND** it SHALL be compatible with `FetchError.from_error` method
- **AND** the error kind SHALL be `ErrorKind::InvalidFormat`

### Requirement: Error context preservation
The `ResponseTooLargeError` SHALL preserve error context.

#### Scenario: Error context in exception
- **WHEN** raising `ResponseTooLargeError`
- **THEN** the exception SHALL include:
  - The URL that caused the error
  - The actual response size
  - The configured limit
- **AND** the context SHALL be accessible via properties
