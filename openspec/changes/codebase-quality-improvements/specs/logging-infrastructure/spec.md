# Logging Infrastructure Specification

## ADDED Requirements

### Requirement: Replace puts statements with Log module
The system SHALL use Crystal's built-in `Log` module for debug and informational output instead of `puts` statements.

#### Scenario: Use structured logging
- **WHEN** debug output is needed
- **THEN** the code SHALL use `Log.debug` calls
- **AND** log output SHALL be controlled via standard Crystal log configuration
- **AND** log messages SHALL include structured context (URL, driver, etc.)

### Requirement: Environment-based log level configuration
Log levels SHALL be configurable via environment variables for runtime configuration.

#### Scenario: Debug mode via environment
- **WHEN** the `FETCHER_DEBUG` environment variable is set
- **THEN** the log level SHALL be set to `:debug` 
- **AND** debug messages SHALL be visible in console output

- **AND** sensitive information (URLs, headers) SHALL be logged with appropriate care

### Requirement: Remove hardcoded puts statements
The codebase SHALL NOT contain `puts` statements for debug output.

#### Scenario: Clean debug output
- **WHEN** reviewing the codebase
- **THEN** there SHALL be no `puts "DEBUG:..."` statements
- **AND** all debug output SHALL go through `Log` module
- **AND** the code SHALL pass ameba lint checks for puts usage

### Requirement: Structured log context
Log messages SHALL include relevant context for debugging.

#### Scenario: Log message format
- **WHEN** logging fetch operations
- **THEN** log messages SHALL include:
  - URL being fetched
  - Driver type being used
  - Error details (if applicable)
  - Timestamp (automatic via Log module)
- **AND** the log format SHALL be consistent across all modules
