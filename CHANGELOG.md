# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Redirect control configuration
- SSL verification options

## [0.7.0] - 2026-03-15

### BREAKING CHANGES

#### Async API Removed
All `*_async` methods have been removed. Crystal's native fiber support makes these wrappers redundant.

**Migration:**
```crystal
# Before (v0.6.x)
channel = Fetcher.pull_async(url)
result = channel.receive

# After (v0.7.0+)
channel = Channel(Fetcher::Result).new
spawn { channel << Fetcher.pull(url) }
result = channel.receive

# For multiple URLs:
results = Array(Fetcher::Result).new
channels = urls.map do |url|
  ch = Channel(Fetcher::Result).new
  spawn { ch << Fetcher.pull(url) }
  ch
end
channels.each { |ch| results << ch.receive }
```

**Removed methods:**
- `Fetcher.pull_async(url, ...)`
- `Fetcher.pull_async(url, headers, etag, last_modified, ...)`
- `Fetcher.pull_rss_async(url, ...)`
- `Fetcher.pull_reddit_async(url, ...)`
- `Fetcher.pull_software_async(url, ...)`
- `Fetcher.pull_json_feed_async(url, ...)`

### Added

#### Circuit Breaker
Production-grade circuit breaker for resilience when fetching thousands of feeds:
- **Per-domain circuit breakers** - Tracks failures independently for each domain
- **State machine** - Closed → Open → HalfOpen → Closed transitions
- **Configurable thresholds** - Set via `RequestConfig`:
  - `circuit_breaker_failure_threshold: Int32 = 5`
  - `circuit_breaker_recovery_timeout: Time::Span = 60.seconds`
  - `circuit_breaker_enabled: Bool = true`
- **CircuitBreaker::Registry** - Access circuit breaker state for monitoring

### Removed

#### Dead Code Cleanup
Removed ~500+ lines of over-engineered code:
- `adaptive_concurrency_controller.cr` - System resource monitoring belongs in app code
- `simple_json_streaming_parser.cr` - Fake streaming (used `JSON.parse`)
- `working_json_streaming_parser.cr` - Fake streaming (used `gets_to_end`)
- `simple_xml_streaming_parser.cr` - Duplicate/unused
- `connection_pool.cr` - Unused, CrestHttpClient has its own client caching

### Changed

#### Simplified ConcurrentFetcher
Replaced complex adaptive concurrency with simple semaphore pattern:
- ~30 lines vs ~270 lines
- Same external behavior
- `max_concurrent` parameter (default: 16)

#### Consolidated Streaming Parsers
Single streaming parser per format:
- `xml_streaming_parser.cr` - Real XML streaming with `XML::Reader`
- `json_streaming_parser.cr` - Real JSON streaming with `JSON::PullParser`

### Tests
- Added 17 new circuit breaker tests
- Total: 135 passing tests

## [0.6.4] - 2026-03-15

### Fixed
- **HTTP::Client.new** - Fixed Crystal 1.18 compatibility by passing proper URI to HTTP::Client constructor

## [0.6.3] - 2026-03-15

### Changed
- **HTTP Client** - Replaced h2o dependency with crest (mamantoha/crest) for better compatibility with newer Crystal versions

### Removed
- Circuit breaker functionality (was tied to h2o)
- HTTP/2 support (via h2o)

## [0.6.2] - 2026-03-14

### Added
- **Adaptive Buffer Sizing** - Dynamic buffer sizing for optimal streaming performance based on content type and size
- **Buffer Pool** - Memory pool for reusable buffers to reduce GC pressure
- **Connection Pool** - HTTP connection reuse for efficient high-frequency fetching
- **Reddit Response Parsing** - Exposed `parse_reddit_response` as public method

### Fixed
- **Code Quality Issues**
  - Removed unused variables (`old_permits`, `error_url`)
  - Fixed unused rescue variables
  - Fixed failing domain_batch_processor test
  - Reduced cyclomatic complexity in multiple methods
  - Enhanced SSRF protection with comprehensive IPv6 support
  - Implemented real system resource monitoring

## [0.6.1] - 2026-03-11

### Fixed

- **Reddit User-Agent** - Changed from bot-like to browser-like User-Agent to avoid Reddit blocking requests

## [0.6.0] - 2026-03-11

### Added

#### Enhanced Software Release Fetching

- **GitHub body extraction** - `entry.content` and `entry.content_html` now contain release notes from the `body` field
- **GitLab REST API support** - Uses `api/v4/projects/{id}/releases` for richer data
- **GitLab fallback chain** - API → releases.atom → tags.atom (automatically tries tags if releases 404)
- **Codeberg REST API support** - Uses `api/v1/repos/{owner}/{repo}/releases` with Atom fallback
- **Self-hosted GitLab detection** - Any URL with `/-/releases` pattern is auto-detected (e.g., `gitlab.company.com/owner/repo/-/releases`)
- **Version extraction from Atom** - Extracts semantic version numbers from Atom feed titles

### Changed

- URL detection regex updated to support any GitLab instance (not just gitlab.com)

### Tests

- Added 24 new tests for software release functionality
- Total: 133 passing tests

## [0.5.1] - 2026-03-09

### Fixed
- **Critical Reddit feed regression** - Fixed double compression issue causing Reddit feeds to fail
  - Removed `Accept-Encoding` header from default headers
  - HTTP::Client handles compression automatically when `compress = true`
  - Reddit JSON API responses now parse correctly
  - All Reddit feeds working again (25 entries per feed)
  - Thanks to @kritoke for quickheadlines testing and reporting

### Technical Details
The issue was caused by setting both `Accept-Encoding: gzip, deflate` header AND `client.compress = true`:
1. HTTP::Client automatically adds Accept-Encoding when compress is enabled
2. Server sees the header and compresses the response
3. HTTP::Client decompresses the response
4. But with manual Accept-Encoding header, the response was double-compressed
5. JSON.parse failed with binary garbage instead of valid JSON

**Solution:** Let HTTP::Client handle compression automatically without manual headers.

## [0.5.0] - 2026-03-09

### What's New

#### Content-Type Based Detection
Smarter feed format detection with HTTP content-type sniffing:
- **HEAD request detection** - Analyzes Content-Type headers before fetching
- **Graceful fallback** - Falls back to URL pattern matching when HEAD fails
- **More reliable** - Reduces misclassification of feed types
- **Backward compatible** - Existing code continues to work unchanged

#### Unified HTTP Client Architecture
Centralized HTTP handling with proper configuration:
- **Single HTTP client** - All drivers use the same HTTP client instance
- **Full configuration support** - Timeouts, headers, compression, and retries
- **Proper resource management** - Consistent connection handling
- **Better error handling** - Unified error categorization

#### Token Bucket Rate Limiting
Scalable rate limiting supporting complex scenarios:
- **Token bucket algorithm** - Better than simple request counting
- **Configurable burst capacity** - Allow temporary spikes in request rate
- **Per-domain rate limits** - Independent limiting for each domain
- **Thread-safe** - Handles concurrent requests without starvation
- Configure via `RequestConfig.rate_limit_capacity` and `rate_limit_refill_rate`

#### RFC-Compliant Time Parsing
Standards-compliant time parsing for all feed formats:
- **RFC 2822 support** - Proper RSS date parsing
- **RFC 3339/ISO 8601** - Atom and JSON Feed format support
- **Timezone preservation** - Properly handles timezone information
- **Fallback formats** - Common date-only formats handled gracefully

#### Streaming Processing
Memory-safe feed processing with streaming:
- **Stream parsing** - XML and JSON feeds parsed incrementally
- **Hard memory limits** - 10MB limit prevents OOM errors
- **Compression awareness** - Accounts for compressed content
- **Early termination** - Stops on size violations

#### Enhanced Security
- **Standard URL validation** - Uses system libraries instead of custom checks
- **SSRF protection** - Comprehensive private IP blocking (IPv4 and IPv6)
- **XML parser hardening** - NONET option prevents network access during parsing

#### Separated Concerns
Clear separation of responsibilities:
- **EntryParser** - Interface for driver-specific parsing
- **EntryFactory** - Creates validated entries
- **ResultBuilder** - Constructs structured results
- Better testability and maintainability

#### Comprehensive Testing
- **126 passing tests** - Extensive test coverage
- **Real fixtures** - Tests with actual RSS/Atom/JSON/Reddit feeds
- **Property-based testing** - Edge case coverage
- **Integration tests** - End-to-end validation

### Compatibility
✅ **Fully backward compatible** - All existing code continues to work unchanged
✅ **No breaking changes** - New fields have sensible defaults
✅ **Opt-in features** - Advanced features disabled by default

### Technical Improvements
- Reduced code duplication across drivers
- Better error categorization and handling
- Cleaner architecture with parser/factory/builder pattern
- Improved memory safety and performance
- Better test coverage (126 tests, all passing)

---

## [0.4.1] - 2026-03-04

### Fixed
- Add missing `sanitize` dependency to `shard.yml` for HTML content sanitization

---

## [0.4.0] - 2026-03-04

### What's New

#### Structured Error Handling
Better error handling with typed errors:
- **ErrorKind enum** - Categorized error types: DNSError, Timeout, InvalidURL, InvalidFormat, HTTPError, RateLimited, ServerError, Unknown
- **Error record** - Structured error with kind, message, status_code, url, and driver context
- **Backward compatible** - Still supports `error_message` accessor

#### Type-Safe Source Types
- **SourceType enum** - Compile-time type safety for feed sources
- Values: RSS, Atom, JSONFeed, Reddit, GitHub, GitLab, Codeberg
- Eliminates magic strings from the API

#### Enhanced Security
- **XML Parser Hardening** - Added NONET option to prevent network access during XML parsing
- **SSRF Protection** - Comprehensive blocking of private IP ranges (IPv4 and IPv6)
- Blocks: 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, ::1, fe80::/10, fc00::/7

#### Rate Limiting
- **Per-domain rate limiting** - Prevent API abuse with configurable rate limits
- Configure via `RequestConfig.max_requests_per_second`
- Thread-safe implementation with minimal overhead

### Compatibility
✅ **Fully backward compatible** - All existing code continues to work unchanged
✅ **No breaking changes** - All new fields have sensible defaults
✅ **Opt-in features** - Rate limiting is disabled by default

### Technical Reference
For detailed API documentation, see [API.md](API.md).

---

## [0.3.0] - 2026-03-01

### What's New

#### Rich Content Extraction
Get more from your feeds with automatic extraction of:
- **Full article content** - No more just summaries; get complete posts from RSS and Atom feeds
- **Author information** - Names and profile links automatically extracted
- **Categories and tags** - Organize content with feed-provided metadata
- **Media attachments** - Podcasts, downloads, and images captured in structured format
- **Feed-level details** - Title, description, language, and authors from the feed itself

#### JSON Feed Support
Now supports JSON Feed format (v1.0 and v1.1) in addition to RSS and Atom:
- Automatic detection for `.json` and `/feed.json` URLs
- Full feature parity with RSS/Atom feeds
- No code changes needed - just works

#### Better Reliability
- **Automatic fallbacks** - Reddit feeds gracefully fall back to RSS when the JSON API is unavailable
- **Configurable timeouts** - Handle slow feeds with custom connection and read timeouts
- **HTTP compression** - Faster loading with automatic gzip/deflate support

#### Enhanced Test Coverage
Comprehensive test suite added to ensure reliability across all feed types and features.

### Compatibility
✅ **Fully backward compatible** - All existing code continues to work unchanged
✅ **No breaking changes** - All new fields have sensible defaults
✅ **Opt-in features** - New capabilities are available when you need them

### Technical Reference
For detailed API documentation, field names, and code examples, see [API.md](API.md).

---

## [0.2.1] - Previous Release

### Changed
- Bumped version number
- Removed compiled binary from tracking

### Fixed
- Various bug fixes from code review

---

## [0.2.0] - Major Refactor

### Changed
- Complete rewrite for v0.2.0
- Functional architecture
- Removed connection pooling for simplicity

[Unreleased]: https://github.com/kritoke/fetcher.cr/compare/v0.7.0..HEAD
[0.7.0]: https://github.com/kritoke/fetcher.cr/compare/v0.6.4..v0.7.0
[0.6.4]: https://github.com/kritoke/fetcher.cr/compare/v0.6.3..v0.6.4
[0.6.3]: https://github.com/kritoke/fetcher.cr/compare/v0.6.2..v0.6.3
[0.6.2]: https://github.com/kritoke/fetcher.cr/compare/v0.6.1..v0.6.2
[0.6.1]: https://github.com/kritoke/fetcher.cr/compare/v0.6.0..v0.6.1
[0.6.0]: https://github.com/kritoke/fetcher.cr/compare/v0.5.1..v0.6.0
[0.5.1]: https://github.com/kritoke/fetcher.cr/compare/v0.5.0..v0.5.1
[0.5.0]: https://github.com/kritoke/fetcher.cr/compare/v0.4.1..v0.5.0
[0.4.1]: https://github.com/kritoke/fetcher.cr/compare/v0.4.0..v0.4.1
[0.4.0]: https://github.com/kritoke/fetcher.cr/compare/v0.3.0..v0.4.0
[0.3.0]: https://github.com/kritoke/fetcher.cr/compare/v0.2.1..v0.3.0
[0.2.1]: https://github.com/kritoke/fetcher.cr/compare/v0.2.0..v0.2.1
[0.2.0]: https://github.com/kritoke/fetcher.cr/compare/v0.1.1..v0.2.0
