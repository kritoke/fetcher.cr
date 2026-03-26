# Response Size Validation Specification

## ADDED Requirements

### Requirement: Dedicated exception type for response size errors
The system SHALL raise a dedicated `ResponseTooLargeError` exception when the HTTP response body exceeds configured limits.

#### Scenario: Response exceeds size limit
- **WHEN** an HTTP response body exceeds `SafeFeedProcessor::MAX_FEED_SIZE` (10MB by default)
- **THEN** the system SHALL raise `ResponseTooLargeError` 
- **AND** the error message SHALL include the actual size and the limit (e.g., "Response too large (>10MB)")
- **AND** the exception SHALL be caught in CrestHttpClient before being passed to downstream error handling

- **AND** the original exception type (DNSError) SHALL NOT be used for this error

### Requirement: Size check in HTTP client
The HTTP client SHALL validate response sizes before raising exceptions.

#### Scenario: Check size before creating response object
- **WHEN** a response is received from Crest.get()
- **THEN** the system SHALL check `response.body.bytesize` against `MAX_FEED_SIZE`
- **AND** if exceeded, it SHALL raise `ResponseTooLargeError` immediately without further processing
- **AND** the response body SHALL not be fully read into memory

### Requirement: Proper error type in size validation
The system SHALL use `ResponseTooLargeError` instead of `DNSError` for size validation failures.

#### Scenario: Size validation in different modules
- **WHEN** a feed exceeds size limits in RSS, JSONFeed, Reddit, or Software modules
- **THEN** each module SHALL raise `ResponseTooLargeError` 
- **AND** it SHALL NOT raise `DNSError` (which is semantically incorrect)
- **AND** the error message SHALL indicate the actual limit (e.g., "10MB")
