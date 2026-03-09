## Why

The current fetcher.cr implementation suffers from architectural flaws that make it fragile, difficult to maintain, and prone to security vulnerabilities. The regex-based driver detection, duplicate HTTP logic, weak error handling, and custom URL validation create a maintenance burden and potential security risks. This refactor addresses these core issues to create a robust, maintainable, and secure feed fetching library.

## What Changes

- **Content-Type Based Detection**: Replace fragile URL regex detection with proper HTTP content-type sniffing for reliable driver selection
- **Unified HTTP Client**: Consolidate all HTTP handling into a single configurable client with proper connection management
- **Structured Error Handling**: Implement typed exception hierarchy instead of string-based error detection
- **Standard URL Validation**: Replace custom IP validation with system libraries and proper SSRF protection
- **Separated Concerns**: Clear separation between parsing, validation, and entry creation
- **Comprehensive Testing**: Real integration tests with canonical feed fixtures and property-based testing
- **Token Bucket Rate Limiting**: Replace naive global mutex rate limiting with scalable token bucket algorithm
- **RFC Time Parsing**: Use standard-compliant time parsing instead of custom format lists
- **Streaming Processing**: Add memory-safe streaming feed processing with hard limits
- **Consistent Configuration**: Unified configuration passing through entire call chain

## Capabilities

### New Capabilities
- `content-type-detection`: Content-type based feed format detection with fallback mechanisms
- `unified-http-client`: Centralized HTTP client with full configuration support and resource management
- `structured-error-handling`: Typed exception hierarchy with clear error categories and contexts
- `standard-url-validation`: Proper URL validation using established libraries with SSRF protection
- `separated-concerns`: Clear parser/factory/builder pattern for feed processing
- `comprehensive-testing`: Integration test framework with real feed fixtures and property-based testing
- `token-bucket-rate-limiting`: Scalable rate limiting supporting complex scenarios
- `rfc-time-parsing`: Standards-compliant time parsing for all feed formats
- `streaming-processing`: Memory-safe streaming feed processing with compression awareness
- `consistent-configuration`: Unified configuration propagation across all components

### Modified Capabilities
- `feed-parsing`: Requirements for parsing logic to handle streaming and memory limits
- `http-handling`: Requirements for HTTP client behavior including timeouts and retries
- `error-handling`: Requirements for error categorization and programmatic handling
- `url-validation`: Requirements for security validation and private IP blocking

## Impact

- **Core Modules**: `src/fetcher.cr`, `src/fetcher/http_client.cr`, `src/fetcher/rss.cr`, `src/fetcher/reddit.cr`, `src/fetcher/software.cr`, `src/fetcher/json_feed.cr`
- **Data Structures**: `Entry` and `Result` records will be enhanced with new fields and validation
- **Public API**: Some method signatures will change (BREAKING) but core `Fetcher.pull` interface remains compatible
- **Dependencies**: May require additional Crystal standard library usage for proper validation
- **Testing**: Complete overhaul of test suite with real fixtures and comprehensive coverage
- **Performance**: Improved memory usage and connection handling for large feeds
- **Security**: Enhanced protection against SSRF and other URL-based attacks