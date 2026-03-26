# Streaming Parser Optimization Specification

## MODIFIED Requirements

### Requirement: True lazy streaming for XML feeds
The XML streaming parser SHALL parse entries incrementally without loading all entries into memory simultaneously.

#### Scenario: Lazy iteration over feed entries
- **WHEN** iterating through feed entries via `EntryIterator`
- **THEN** the system SHALL parse entries one at a time
- **AND** only one entry SHALL be held in memory at a time
- **AND** the parser SHALL use `XML::Reader` to stream through the document without loading the entire document

- **AND** memory usage SHALL remain bounded (approximately O(entries × average_entry_size)

### Requirement: True lazy streaming for JSON feeds
The JSON streaming parser SHALL parse entries incrementally without loading all entries into memory simultaneously.

#### Scenario: Lazy iteration through JSON entries
- **WHEN** iterating through feed entries via `JSONStreamingIterator`
- **THEN** the system SHALL parse entries one at a time
- **AND** only one entry SHALL be held in memory at a time
- **AND** the parser SHALL use `JSON::PullParser` to stream through the document
- **AND** memory usage SHALL remain bounded (approximately O(entries * average_entry_size)

### Requirement: Iterator interface compliance
Both streaming parsers SHALL implement the `Iterator(Entry)` interface.

#### Scenario: Iterator next method
- **WHEN** calling `next` on an entry iterator
- **THEN** it SHALL return `Entry` or `Iterator::Stop`
- **AND** it SHALL parse the next entry lazily
- **AND** it SHALL maintain position in the stream

## ADDED Requirements

### Requirement: Streaming configuration option
The RequestConfig SHALL include a `use_streaming_parser` option to enable streaming parsing.

#### Scenario: Enable streaming via config
- **WHEN** `config.use_streaming_parser` is true
- **THEN** the system SHALL use streaming parsers for RSS, Atom, JSONFeed, and Reddit feeds
- **AND** the streaming parser SHALL parse entries lazily
- **AND** fallback to DOM parser SHALL occur if streaming fails

### Requirement: Memory limit for streaming
Streaming parsers SHALL respect `max_streaming_memory` configuration option.

#### Scenario: Memory limit exceeded
- **WHEN** a feed size exceeds `config.max_streaming_memory`
- **THEN** the streaming parser SHALL raise `MemoryLimitExceeded` error
- **AND** the error SHALL include the actual size and configured limit
- **AND** processing SHALL stop immediately
