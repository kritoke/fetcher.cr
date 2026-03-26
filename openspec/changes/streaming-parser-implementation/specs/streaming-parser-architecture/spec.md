# Streaming Parser Architecture Specification

## ADDED Requirements

### Requirement: Lazy iterator-based streaming parsers
The system SHALL provide lazy iterator-based streaming parsers that process feed entries incrementally without loading the entire document into memory.

#### Scenario: Memory-efficient entry processing
- **WHEN** a user processes a large feed with streaming parser enabled
- **THEN** memory usage SHALL remain constant regardless of feed size
- **AND** entries SHALL be available as they are parsed

#### Scenario: Iterator interface compatibility
- **WHEN** a user requests entries from a streaming parser
- **THEN** the system SHALL return an Iterator(Entry) that implements Crystal's standard iterator protocol
- **AND** users SHALL be able to use standard iterator methods (take, each, to_a, etc.)

### Requirement: Pull parser foundation
The system SHALL use Crystal's built-in pull parsers (XML::Reader and JSON::PullParser) as the foundation for all streaming parsers.

#### Scenario: XML feed streaming
- **WHEN** processing an XML/RSS/Atom feed with streaming parser
- **THEN** the system SHALL use XML::Reader for sequential parsing
- **AND** it SHALL leverage libxml2's xmlReader for memory efficiency

#### Scenario: JSON feed streaming
- **WHEN** processing a JSON/Reddit feed with streaming parser
- **THEN** the system SHALL use JSON::PullParser for sequential parsing
- **AND** it SHALL use the same engine as JSON.from_json for consistency

### Requirement: Automatic fallback to DOM parsing
The system SHALL automatically fallback to DOM parsing when streaming parsing fails for any reason.

#### Scenario: Malformed feed handling
- **WHEN** a malformed feed causes streaming parser to fail
- **THEN** the system SHALL automatically retry with DOM parser
- **AND** it SHALL return the same Result structure as successful parsing
- **AND** it SHALL log a warning about the fallback

#### Scenario: Seamless error handling
- **WHEN** any exception occurs during streaming parsing
- **THEN** the system SHALL catch the exception
- **AND** it SHALL invoke the existing DOM parser with identical parameters
- **AND** users SHALL not need to handle streaming-specific errors

### Requirement: Configuration-driven opt-in
The system SHALL require explicit opt-in for streaming parsing via RequestConfig.

#### Scenario: Default behavior
- **WHEN** no streaming configuration is provided
- **THEN** the system SHALL use DOM parsing by default
- **AND** existing behavior SHALL remain unchanged

#### Scenario: Explicit streaming enable
- **WHEN** use_streaming_parser is set to true in RequestConfig
- **THEN** the system SHALL attempt streaming parsing first
- **AND** it SHALL fallback to DOM parsing on errors

### Requirement: Memory limit enforcement
The system SHALL enforce configurable memory limits for streaming operations.

#### Scenario: Memory limit configuration
- **WHEN** max_streaming_memory is configured in RequestConfig
- **THEN** the system SHALL respect this limit for streaming buffer sizes
- **AND** it SHALL use 10MB as default when not specified

#### Scenario: Memory limit exceeded
- **WHEN** streaming operation exceeds configured memory limit
- **THEN** the system SHALL raise InvalidFormatError
- **AND** it SHALL include memory limit information in the error message