# Error Logging Specification

## ADDED Requirements

### Requirement: Replace empty rescue blocks with proper error logging
The codebase SHALL not contain empty `rescue` blocks that silently swallow errors.

#### Scenario: Error logging in rescue blocks
- **WHEN** an error occurs in a rescue block
- **THEN** the error SHALL be logged via `Log` module
- **AND** the log level SHALL be `:error` for unexpected errors
- **AND** the log level SHALL be `:warn` for expected but non-critical errors
- **AND** the error context SHALL be preserved (exception class, message, stack trace when available)

### Requirement: Remove unused rescue variables
The codebase SHALL not contain unused rescue variables that clutter the code.

#### Scenario: Clean rescue blocks
- **WHEN** reviewing all rescue blocks in the codebase
- **THEN** there SHALL be no unused rescue variables (ex)
- **AND** rescue blocks that don't need the exception variable SHALL use underscore (_)
- **AND** code SHALL pass ameba lint checks for UnusedRescueVariable

### Requirement: Error context preservation
Error logging SHALL include sufficient context for debugging.

#### Scenario: Log error with context
- **WHEN** logging an error from a rescue block
- **THEN** the log SHALL include:
  - The operation that failed (e.g., "parse_rss_item", "fetch_releases")
  - The URL or feed being processed
  - The exception class
  - The exception message
- **AND** stack traces SHALL be included at `:debug` log level
