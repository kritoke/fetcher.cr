# Error Handling Improvements Specification

## MODIFIED Requirements

### Requirement: Consistent typed exception usage
The system SHALL use typed exceptions consistently throughout all modules instead of mixing typed exceptions and string-based error checking.

#### Scenario: Use typed exceptions in all modules
- **WHEN** any error occurs in RSS, Reddit, Software, or JSONFeed modules
- **THEN** the system SHALL raise appropriate typed exceptions (DNSError, TimeoutError, InvalidURLError, etc.)
- **AND** it SHALL NOT return generic Exception with string messages
- **AND** it SHALL wrap error details in structured Error objects

#### Scenario: Error propagation through retry logic
- **WHEN** a retriable error occurs during with_retry
- **THEN** the system SHALL preserve the exception type through retries
- **AND** it SHALL maintain error context (URL, message, status code)
- **AND** it SHALL not lose error information during retry attempts

### Requirement: Remove unused rescue variables
The codebase SHALL not contain unused rescue variables that clutter the code.

#### Scenario: Clean rescue blocks
- **WHEN** reviewing all rescue blocks in the codebase
- **THEN** there SHALL be no unused rescue variables (ex)
- **AND** rescue blocks that don't need the exception variable SHALL use underscore (_)
- **AND** code SHALL pass ameba lint checks for UnusedRescueVariable

### Requirement: Standardized error response creation
The system SHALL use consistent methods for creating error Result objects.

#### Scenario: Use Fetcher.error_result consistently
- **WHEN** creating an error Result in any module
- **THEN** the code SHALL use Fetcher.error_result helper method
- **AND** it SHALL NOT create Result.error directly except in helper methods
- **AND** error messages SHALL be descriptive and actionable

#### Scenario: Error kind mapping
- **WHEN** an HTTP error occurs
- **THEN** the system SHALL map status codes to appropriate ErrorKinds
- **AND** 4xx errors SHALL map to ErrorKind::HTTPError
- **AND** 5xx errors SHALL map to ErrorKind::ServerError
- **AND** rate limiting (429) SHALL map to ErrorKind::RateLimited

### Requirement: Improved error context
Error objects SHALL include comprehensive context for debugging.

#### Scenario: Include URL in error context
- **WHEN** an error occurs during feed fetching
- **THEN** the Error object SHALL include the URL that caused the error
- **AND** it SHALL include relevant HTTP status codes
- **AND** it SHALL include the driver/module that encountered the error

#### Scenario: Error messages with actionable information
- **WHEN** creating error messages
- **THEN** messages SHALL include specific details (e.g., "Subreddit 'xyz' not found" instead of "Not found")
- **AND** messages SHALL indicate potential causes when possible
- **AND** messages SHALL be user-friendly while maintaining technical accuracy

## ADDED Requirements

### Requirement: Error classification for retry logic
The system SHALL properly classify errors as retriable or non-retriable.

#### Scenario: Classify transient errors
- **WHEN** classifying errors for retry
- **THEN** DNSError, TimeoutError, and 5xx HTTP errors SHALL be retriable
- **AND** InvalidURLError, InvalidFormatError, and 4xx HTTP errors SHALL NOT be retriable
- **AND** RateLimitError SHALL be retriable with appropriate backoff

#### Scenario: Retry with exponential backoff
- **WHEN** a retriable error occurs
- **THEN** the system SHALL retry with exponential backoff
- **AND** it SHALL add jitter to prevent thundering herd
- **AND** it SHALL respect max_retries configuration
