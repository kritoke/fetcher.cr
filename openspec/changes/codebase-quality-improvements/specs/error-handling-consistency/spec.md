# Error Handling Consistency Specification

## ADDED Requirements

### Requirement: Standardized error handling module
The system SHALL use a shared `ErrorHandler` module for consistent error handling across all fetch operations.

#### Scenario: Use shared error handler
- **WHEN** a fetch operation encounters an error
- **THEN** the system SHALL use `ErrorHandler.handle_response` 
- **AND** error handling SHALL be consistent across RSS, Reddit, Software, JSONFeed, and YouTube modules

### Requirement: Response status code handling
The error handler SHALL consistently map HTTP status codes to error types and return values.

#### Scenario: 304 Not Modified
- **WHEN** HTTP response returns status code 304
- **THEN** the system SHALL return an empty Result with etag/last_modified
- **AND** it SHALL not raise an exception

#### Scenario: 4xx Client Errors
- **WHEN** HTTP response returns status code 400-499
- **THEN** the system SHALL return `Result.error(HTTPError)` 
- **AND** it SHALL not raise an exception

#### Scenario: 5xx Server Errors
- **WHEN** HTTP response returns status code 500-599
- **THEN** the system SHALL raise `HTTPServerError` 
- **AND** it SHALL be retriable

#### Scenario: Rate Limited (429)
- **WHEN** HTTP response returns status code 429
- **THEN** the system SHALL raise `RateLimitError` 
- **AND** it SHALL include retry-after header in error context

### Requirement: Error result type preservation
All errors SHALL be wrapped in `Result` objects that returned to callers.

#### Scenario: Return error result
- **WHEN** any non-transient error occurs
- **THEN** the system SHALL return `Result.error(error)` instead of raising
- **AND** the caller can check `result.error?` to determine if an error occurred

### Requirement: Preserve URL context in errors
All error objects SHALL include the URL that caused the error.

#### Scenario: Error with URL context
- **WHEN** creating an Error object
- **THEN** the Error SHALL include the `url` field
- **AND** the URL SHALL be accessible via `error.url`
- **AND** the URL SHALL be included in error messages when debug logging is enabled
