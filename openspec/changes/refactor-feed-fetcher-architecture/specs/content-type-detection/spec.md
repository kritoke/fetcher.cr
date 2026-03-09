## ADDED Requirements

### Requirement: Content-Type Based Detection
The system SHALL use HTTP content-type headers to determine feed format when available, falling back to URL-based detection when content-type is unavailable or HEAD request fails.

#### Scenario: RSS feed with application/rss+xml content-type
- **WHEN** fetching a URL with content-type "application/rss+xml"
- **THEN** system selects RSS driver

#### Scenario: Atom feed with application/atom+xml content-type  
- **WHEN** fetching a URL with content-type "application/atom+xml"
- **THEN** system selects RSS driver (for Atom parsing)

#### Scenario: JSON Feed with application/feed+json content-type
- **WHEN** fetching a URL with content-type "application/feed+json"
- **THEN** system selects JSON Feed driver

#### Scenario: Generic JSON API with application/json content-type
- **WHEN** fetching a URL with content-type "application/json" but without JSON Feed URL patterns
- **THEN** system falls back to URL-based detection and may select RSS driver

#### Scenario: JSON Feed with application/json content-type and correct URL pattern
- **WHEN** fetching a URL with content-type "application/json" AND URL ending in ".json" or containing "/feed.json"
- **THEN** system selects JSON Feed driver

#### Scenario: Server that doesn't support HEAD requests
- **WHEN** HEAD request fails with any error
- **THEN** system falls back to URL-based detection without crashing

#### Scenario: Missing content-type header
- **WHEN** HEAD request succeeds but content-type header is missing
- **THEN** system falls back to URL-based detection

#### Scenario: Backward compatibility with existing API
- **WHEN** calling detect_driver with only URL parameter
- **THEN** system uses default headers and config parameters

### Requirement: Unified HTTP Client with HEAD Support
The system SHALL provide a HEAD method in the HTTPClient module that reuses existing connection handling, rate limiting, and error handling logic.

#### Scenario: HEAD request with valid URL
- **WHEN** calling HTTPClient.head with valid URL
- **THEN** returns HTTP response with headers only

#### Scenario: HEAD request respects timeouts
- **WHEN** calling HTTPClient.head with custom timeout configuration
- **THEN** respects connect_timeout and read_timeout settings

#### Scenario: HEAD request applies rate limiting
- **WHEN** calling HTTPClient.head multiple times to same domain
- **THEN** applies same rate limiting as GET requests

#### Scenario: HEAD request error handling
- **WHEN** HEAD request fails with network error
- **THEN** raises same DNSError as GET requests

### Requirement: Backward Compatible API
The system SHALL maintain backward compatibility with all existing public APIs while adding new functionality.

#### Scenario: Existing code continues to work
- **WHEN** existing code calls Fetcher.pull(url) without changes
- **THEN** behaves identically to previous version

#### Scenario: New functionality available
- **WHEN** new code calls detect_driver with headers and config
- **THEN** uses content-type detection with provided parameters