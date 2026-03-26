# JSON Reddit Streaming Specification

## ADDED Requirements

### Requirement: JSON::PullParser-based Reddit streaming
The system SHALL use JSON::PullParser to process Reddit JSON feeds incrementally without loading the entire document into memory.

#### Scenario: Large Reddit feed processing
- **WHEN** processing a large Reddit JSON feed (> 10MB) with streaming parser enabled
- **THEN** memory usage SHALL remain below 10MB regardless of feed size
- **AND** entries SHALL be processed as they are encountered in the feed

#### Scenario: Reddit API response parsing
- **WHEN** processing Reddit JSON API responses with nested structure (data.children.data)
- **THEN** the system SHALL navigate the JSON structure using pull parser without allocating intermediate Hash objects
- **AND** it SHALL extract individual posts efficiently

### Requirement: Selective JSON skipping strategy
The system SHALL use JSON::PullParser's skip() method to efficiently navigate past irrelevant JSON structures without parsing them into objects.

#### Scenario: Skipping Reddit metadata
- **WHEN** processing Reddit JSON feed
- **THEN** the system SHALL skip irrelevant top-level metadata (before/after, dist, etc.)
- **AND** it SHALL only parse the children array containing actual posts

#### Scenario: Skipping post metadata
- **WHEN** processing individual Reddit posts
- **THEN** the system SHALL skip irrelevant post fields based on required Entry fields
- **AND** it SHALL only extract necessary data (title, url, created_utc, etc.)

### Requirement: Hybrid parsing for Reddit posts
The system SHALL extract individual Reddit post JSON objects and parse them using existing JSON parsing logic.

#### Scenario: Reddit post extraction and parsing
- **WHEN** encountering a Reddit post during streaming
- **THEN** the system SHALL extract the complete post JSON object
- **AND** it SHALL parse the post using existing Reddit.parse_reddit_post() method
- **AND** the resulting Entry SHALL be identical to DOM parser output

### Requirement: Reddit feed metadata extraction
The system SHALL extract subreddit and feed-level metadata during the initial streaming pass.

#### Scenario: Subreddit metadata extraction
- **WHEN** processing Reddit JSON feed with streaming parser
- **THEN** the system SHALL extract subreddit information from the feed structure
- **AND** it SHALL include site_link and favicon in the Result structure

### Requirement: Robust JSON error handling
The system SHALL handle malformed JSON gracefully with appropriate error messages and fallback behavior.

#### Scenario: Malformed JSON handling
- **WHEN** encountering malformed JSON during streaming parsing
- **THEN** the system SHALL raise InvalidFormatError with descriptive message
- **AND** it SHALL trigger automatic fallback to DOM parsing

#### Scenario: Incomplete JSON handling
- **WHEN** encountering incomplete JSON (unclosed braces, missing commas) during streaming
- **THEN** the system SHALL handle it gracefully
- **AND** it SHALL either skip malformed posts or fallback to DOM parsing based on severity

### Requirement: JSON Feed support
The system SHALL also support JSON Feed format using the same JSON::PullParser architecture.

#### Scenario: JSON Feed streaming
- **WHEN** processing JSON Feed format with streaming parser enabled
- **THEN** the system SHALL use JSON::PullParser to extract items incrementally
- **AND** it SHALL process feed metadata before individual entries
- **AND** it SHALL maintain compatibility with existing JSON Feed parsing logic