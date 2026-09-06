# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.22] - 2026-09-04

### Changed

- **Reddit User-Agent**: Now sourced from `Fetcher::VERSION` (sourced from `shard.yml`) instead of a hardcoded string. No more silent version drift on release.
- **`RedditDiagnostics.log_fetch` DNS resolution**: The DNS lookup now lives inside the `Log.debug` block, so it only runs when debug logging is enabled. Previously it ran on every Reddit request regardless of log level.

### Added

- **`Fetcher::VERSION`**: New constant in `src/fetcher/version.cr` providing a programmatic source of truth for the library version. Used by `Reddit::USER_AGENT`.
- **`FeedMetadata#empty?` predicate**: New method that returns true only when every metadata field is nil/empty. Replaces the brittle ad-hoc `unless site_link.nil? && feed_title.nil?` checks that mis-classified feeds with one populated field but not the other.

### Fixed

- **rss_parser dead code**: Removed three unused private methods (`count_entity_definitions`, `extract_rss_favicon`, `extract_atom_categories`).
- **Reddit diagnostics dead code**: Removed unused `HTTP_STATUS_WIDTH` constant.
- **`Fetcher::Reddit` User-Agent**: No longer reports stale version `0.9.7` on every release; now reads `Fetcher::VERSION`.

### Refactored

- **RSS parser**: `XMLHelper` module moved into its own file (`src/fetcher/xml_helper.cr`) so other XML consumers can include it without depending on `rss_parser.cr`. `MAX_ENTITY_DEFINITIONS` is now a proper class constant at the top of `RSSParser`. Local `EMPTY_FEED_METADATA` shim removed; callers use `FeedMetadata::EMPTY`.
- **Reddit module**: ~90 lines of JSON shape parsing (`parse_reddit_response`, `extract_children`, `parse_reddit_post`, `extract_post_data`, `PostData`, field extractors) extracted to `src/fetcher/reddit_post_parser.cr` as `Fetcher::RedditPostParser`. `Fetcher::Reddit.parse_reddit_response` is preserved as a one-line delegation for backwards compatibility.
- **Reddit diagnostics**: `log_fetch_diagnostics` and `build_response_detail` extracted to `src/fetcher/reddit_diagnostics.cr` as `Fetcher::RedditDiagnostics`. The header-lookup helper now walks case-insensitive name pairs instead of four `||` chains.
- **`fetch_old_reddit`**: 5-line wrapper around `fetch_reddit_api` inlined into its single call site in `fetch_fallback`.

---

## [0.9.21] - 2026-07-16

### Changed

- **Crystal 1.19.1**: Raised the minimum Crystal version to 1.19.0 and the Nix dev shell to Crystal 1.19.1. Migrated all monotonic timing from the now-deprecated `Time.monotonic` to `Time.instant` (introduced in Crystal 1.19). Reading-storage fields (`last_accessed`, `last_failure_time`) are now `Time::Instant`; duration fields (`ttl`, `recovery_timeout`) remain `Time::Span`. `TokenBucketRateLimiter` now tracks `@last_refill` as a `Time::Instant` and derives elapsed seconds via `(now - @last_refill).total_seconds`. Also picks up the FreeBSD/macOS kqueue timer fix and the XML memory-leak fixes shipped in Crystal 1.19.x.
- **Crest 1.8.0**: Updated the Crest dependency from 1.7.0 to 1.8.0.

### Added

- **GitHub Atom release fallback**: Software releases now fall back to the GitHub Atom feed when the REST API is unavailable, and Atom entry titles are normalized.
- **DNS cache size cap**: `Fetcher::DnsCache` now enforces a configurable maximum-entries cap with periodic cleanup to prevent unbounded growth under long-running processes.
- **`strip_entry_content` option**: New `RequestConfig` option (`strip_entry_content : Bool = false`) to skip extracting/parsing entry HTML content.
- **Resource cleanup**: Added `Cache#close`, `CacheStore#close`, and `RequestConfig#close` for explicit fiber/resource cleanup.

### Fixed

- **Defensive gzip decompression**: Handles servers that send a gzipped body without a `Content-Encoding` header.
- **DNS cache race**: Self-locked `ensure_cleanup_registered` to close a race in `DnsCache`; the `max_entries` setter now rejects non-positive values.
- **Unbounded growth**: Registered DNS cache and `PeriodicCleanup` cleanup tasks with periodic cleanup to prevent memory growth.
- **Circuit breaker timing**: Failure and recovery windows now use monotonic (`Time.instant`) timing.
- **Redirect success tracking**: Records successful contact after a redirect so the circuit breaker counts the resolved request.
- **Regex precompilation**: Pre-compiled `Software.extract_repo` and other regex patterns.
- Addressed P0–P2 code review findings across URL validation, redirect handling, and error classification.

### Performance

- Optimized `PublicSuffix.get_public_suffix` (eliminated O(n) suffix rebuilding) and precompiled parsing/regex hot paths.

### Removed

- **CrestHttpClient DNS shims**: Dropped five class-level methods that were added in 9el.1 as "preserved public API" shims but had zero production callers in the codebase: `.dns_max_entries`, `.dns_max_entries=`, `.ensure_dns_cleanup_registered`, `.enforce_dns_limit`, `.clear_expired_dns`, and the class-level `.clear_dns_cache`. The corresponding test assertions in `spec/crest_http_client_public_api_spec.cr` are also removed. The actual cache lives on `Fetcher::DnsCache`; callers can use that directly. Also resolves a latent race in `ensure_cleanup_registered` that was only exposed because the shim was callable from external code without holding the lock.

### Internal / Code Quality

- Extracted `DnsCache`, `RebindingChecker`, `RedirectPolicy`, `RegistryStore(T)`, and `PeriodicCleanupHandle` into dedicated classes; added a `copy_with` helper to deduplicate `RequestConfig` `with_*` methods. Replaced 10+ IP-range checks in `URLValidator` with a CIDR table. Removed dead records, constants, and unused shims across the registries and `CrestHttpClient`. Applied the Crystal 1.19 formatter.

---

## [0.9.13] - 2026-05-16

### Bug Fixes

- **ReleaseHelpers Class Methods**: Crystal's `include` doesn't bring in class methods (`def self.*`). Changed all helper methods to `def self.*` syntax. GitHub, GitLab, and Codeberg now call `ReleaseHelpers.method_name` explicitly.
- **CrestHttpClient.clear_dns_cache**: Added class method convenience wrapper `self.clear_dns_cache`.

---

## [0.9.12] - 2026-05-16

### Security

- **SSRF Protection Confirmed**: Documented SSRF protection is properly enforced via `CrestHttpClient.check_ssrf()` and `URLValidator`. All HTTP requests flow through validated boundaries.

### Bug Fixes

- **Semaphore Race Condition**: Fixed potential deadlock in `CrestHttpClient` where concurrent requests could call `acquire_semaphore` before the semaphore was fully initialized. Now uses lazy initialization with mutex for thread-safe setup.
- **Fiber Error Handling**: Added error handling to `TokenBucketRateLimiter.try_schedule_wakeup` spawned fiber. Previously, unhandled exceptions in wakeup fibers would silently terminate.

### Code Quality

- **Result.success() Refactoring**: Reduced `Result.success()` from 9 to 3 parameters (entries, etag, last_modified). All callers now use the `Result.builder` pattern for optional metadata. Added `Result.with_site_link()` helper for test compatibility.
- **CacheStore Handler Decomposition**: Extracted 5 named handlers (`handle_enabled_set`, `handle_enabled_get`, `handle_max_size_set`, `handle_max_size_get`, `handle_cleanup`) from the 10-branch case expression for improved testability.
- **Reddit Deep Nesting**: Refactored `extract_post_data` from 8 nesting levels to 3, extracting helper methods: `extract_title`, `extract_permalink`, `build_discussion_url`, `determine_effective_url`, `extract_pub_date`.
- **RSS Parser Message Chains**: Created `XMLHelper` module with reusable XPath helpers (`xpath_text`, `find_child`, `find_attr`, `find_link`, `extract_href`) to reduce Law of Demeter violations.
- **Software Release Consolidation**: Created `release_helpers.cr` module with shared parsing helpers (`extract_tag`, `extract_name`, `extract_html_url`, `parse_release_date`, `prerelease?`) used by GitHub, GitLab, and Codeberg providers.

---

## [0.9.4] - 2026-04-22

### New Features

- **Reddit OAuth**: Added Reddit OAuth2 password grant authentication to bypass datacenter IP blocks (the "whoa there, pardner!" 403). Configure via `reddit_client_id`, `reddit_client_secret`, `reddit_username`, and `reddit_password` on `RequestConfig`. Tokens are cached and auto-refreshed with thread-safe acquisition. Falls back to unauthenticated requests when credentials are not configured.

### New RequestConfig Options

- `reddit_client_id : String?` - Reddit OAuth client ID (registered at reddit.com/prefs/apps)
- `reddit_client_secret : String?` - Reddit OAuth client secret
- `reddit_username : String?` - Reddit account username for authentication
- `reddit_password : String?` - Reddit account password for authentication

### Internal Improvements

- Cache injection API: `Cache.new(max_size, enabled, store : CacheStore? = nil)` allows injecting a shared CacheStore for global caching without breaking existing instance-local behavior.
- Clarified Cache behavior in docs: Cache retains both class-level (shared default) and instance-level stores. Added helpers: `Cache.default_store=` and `Cache.use_default_store` to configure the shared store.
- Reddit OAuth token expiry stored as an absolute timestamp (expires_at is now a Time). This is an internal change; public API remains unchanged.
- `URLValidator.looks_like_ip?` now uses `Socket::IPAddress` parsing when possible for more robust IP detection.

## [0.9.3] - 2026-04-20

### Security

- **SSRF Protection**: Fixed 18 security vulnerabilities including SSRF bypasses, XSS, open redirects, and DoS vectors
- **URL Validation**: Fixed deadlock in URLValidator cache enforcement and double-slash in path normalization
- **IPv6 Detection**: Fixed IPv6 detection bug in URLValidator

### Bug Fixes

- **Reddit Fallback**: Improved Reddit diagnostics and added RSS fallback on 403 responses
- **Reddit Cache**: Added old.reddit.com as third-tier fallback with extended cache TTLs
- **Semaphore Deadlock**: Fixed semaphore deadlock in high-concurrency scenarios
- **TokenBucket**: Use monotonic timing for refills; add owner-fiber error recovery

### Architecture

- **Thread Safety**: Introduced actor-based stores (CacheStore, CircuitBreakerStore, RateLimiterStore, ValidatedIpStore) for improved thread safety
- **PeriodicCleanup**: Track tasks per-block to avoid global cross-talk
- **Code Sharing**: Refactored Codeberg/GitLab to share release fetching logic

### Internal Improvements

- Improved code quality and readability across the codebase
- Added stress tests for TokenBucket and Cache
- Better error diagnostics and logging

### New RequestConfig Options

- `gitlab_token : String?` - Optional GitLab API token for authenticated requests
- `codeberg_token : String?` - Optional Codeberg API token for authenticated requests
- `ssl_verify_bypass_acknowledged : Bool` - Acknowledge SSL verification bypass (for testing with self-signed certs)

## [0.9.2] - 2026-04-05

### Bug Fixes

- **URL Validation**: Restructured URLValidator into two tiers — `valid?` is now fast (no DNS) for hostnames, `resolve_and_validate` only does DNS for explicit IP addresses
- **SSRF Resilience**: `check_ssrf` now logs a warning instead of raising an error when DNS resolution fails, preventing blocked requests on transient DNS issues

### Tests

- Added 21 unit tests for URLValidator covering hostname acceptance, localhost rejection, private/public IP handling, URL length limits, query strings, and DNS failure resilience

## [0.9.1.3] - 2026-04-05

### Bug Fixes

- **URL Validation**: Fixed validate_ip_address to return true for hostnames. Socket::IPAddress.new only parses IPs, not hostnames, so it was raising Socket::Error and returning false - blocking all URLs with hostnames.

### Bug Fixes

- **DNS Resolution**: Fixed URLValidator.resolve_and_validate to use proper DNS lookup (Socket::Addrinfo.resolve) instead of Socket::IPAddress.new. This enables SSRF protection for URLs with hostnames, not just explicit IPs.

## [0.9.1.1] - 2026-04-05

### Bug Fixes

- Fixed nilable title passing to Entry.create in RSS parser (regression from N+1 XPath refactoring)

## [0.9.1] - 2026-04-05

### Security

- **SSRF Protection**: Fixed fail-open on DNS resolution failures (return false instead of allowing request)
- **XXE Prevention**: Removed `NOENT` XML parser flag that could enable entity expansion attacks
- **Redirect Resolution**: Fixed path traversal risk by replacing `File.join` with proper `URI.resolve`
- **SSL Verification**: Fixed `ssl_verify` config not being wired through to HTTP client
- **URL Length Limit**: Added 2048 character max URL length validation

### Bug Fixes

- **DNS Rebinding**: Added IP validation tracking to mitigate TOCTOU attacks
- **Race Conditions**: Fixed concurrent cleanup spawn in CircuitBreaker and RateLimiterRegistry
- **Error Handling**: Fixed silent error swallowing in XML streaming parser
- **Rate Limiting**: Fixed double rate limiting on cross-domain redirects
- **Streaming Parser**: Fixed non-seekable IO handling in JSON streaming parser

### Performance

- **XML/JSON Parsing**: Eliminated double parsing by parsing once and reusing document
- **XPath Queries**: Fixed N+1 XPath queries by extracting child nodes in single pass
- **Cache Eviction**: Simplified from O(n) LRU to O(1) FIFO

### Maintenance

- **Error Classification**: Added `MissingLocationHeaderError` for proper redirect error categorization
- **Code Cleanup**: Removed redundant `ResultBuilder` module, fixed broken error_result overload

## [0.9.0] - 2026-04-01

### What's New

#### Structured Configuration (Required)

`RequestConfig` now uses composable sub-config objects instead of flat parameters. This makes configuration more organized and explicit about what you're configuring.

```crystal
config = Fetcher::RequestConfig.new(
  timeout: Fetcher::TimeoutConfig.new(connect: 30.seconds, read: 60.seconds),
  retry: Fetcher::RetryConfig.new(max_retries: 5),
  circuit_breaker: Fetcher::CircuitBreakerConfig.new(failure_threshold: 5),
  rate_limit: Fetcher::RateLimitConfig.new(requests_per_second: 10),
  streaming: Fetcher::StreamingConfig.new(enabled: true),
  cache_config: Fetcher::CacheConfig.new(max_size: 500)
)
```

#### Cache Goes Class-Based

`Cache` is now a proper class instead of a module. This means you can create isolated cache instances — great for testing or running multiple independent feeds in the same app.

```crystal
# Shared singleton (works exactly like before)
Fetcher::Cache.get("my-key")
Fetcher::Cache.set("my-key", result, 5.minutes)

# Or create your own isolated cache
cache = Fetcher::Cache.new(max_size: 100)
cache.get("my-key")
```

#### Reddit Cache Helpers Moved

Reddit-specific cache helpers (`generate_key`, `ttl_for_sort`, `clear_subreddit`) now live on the `Reddit` module where they belong. The old `Cache.*` methods still work as thin wrappers, so nothing breaks.

```crystal
# Preferred (new)
Fetcher::Reddit.generate_cache_key("crystal", "hot", 25)
Fetcher::Reddit.ttl_for_sort("hot")
Fetcher::Reddit.clear_cache("crystal")

# Still works (delegates to Reddit)
Fetcher::Cache.generate_key("crystal", "hot", 25)
Fetcher::Cache.ttl_for_sort("hot")
Fetcher::Cache.clear_subreddit("crystal")
```

#### Reddit Fallback Actually Works Now

The Reddit JSON API fallback to RSS was broken — the error handling path was unreachable. Now the fallback is properly wired: if the JSON API fails with a transient error (timeout, DNS, server error), it retries first, then falls back to the RSS feed. Non-transient errors (like 404 for a missing subreddit) are returned immediately without falling back.

#### Readability Pass

A thorough code review cleaned up the codebase:

- `FeedMetadata` updates use `copy_with` instead of 50-line rebuilds
- `head` and `get` share a single `perform_request` method
- Redirect handling extracts domain transition logic into a helper
- `Cache.get` uses guard clauses instead of nested if/else
- `URLValidator` uses a `blocked_ip?` predicate instead of 6 negated terms
- Manual `mutex.lock`/`unlock` replaced with `synchronize` everywhere
- Dead code removed (unused `@waiters` field, unused `parse_reddit_post` method, duplicate extract helpers)
- Variable shadowing fixed in Reddit module
- `CircuitBreaker#check_recovery` separated into pure query + caller-side transition

### Breaking Changes

| Old API | New API |
|---------|---------|
| `config.connect_timeout` | `config.timeout.connect` |
| `config.read_timeout` | `config.timeout.read` |
| `config.max_retries` | `config.retry.max_retries` |
| `config.rate_limit_capacity` | `config.rate_limit.capacity` |
| `config.circuit_breaker_enabled` | `config.circuit_breaker.enabled` |
| `config.use_streaming_parser` | `config.streaming.enabled` |
| `config.cache_enabled` | `config.cache_config.enabled` |

`Cache` changed from `module` to `class`. Backward-compatible class methods (`Cache.get`, `Cache.set`, `Cache.clear`, `Cache.stats`) still work via `Cache.default` delegation. For isolated caches, create instances with `Cache.new(max_size: 100)`.

Cache key format changed from `fetcher:reddit:*` to `reddit:*`. Any cached data from before this version won't be found by the new code (but will work for new fetches going forward).

`FetchError.from_error` was removed (was dead code, never called in the codebase).

## [0.8.3] - 2026-03-28

### Fixed

- **RSS 2.0 `<comments>` element extraction** - The `<comments>` element is now properly extracted as a fallback when no `<link rel="comments">` or `<link rel="replies">` is present
  - DOM parser (`RSSParser`) now extracts `<comments>` element
  - Streaming parser (`StreamingRSSParser`) now extracts `<comments>` element
  - `comment_url` field is populated from `<comments>` element as fallback
- **Streaming parser bug fixes** - Fixed pre-existing bugs that prevented streaming parser from working:
  - Fixed `node_type` comparison (was comparing enum to Symbol)
  - Fixed depth tracking for item/entry parsing
  - Added missing `comment_url`, `commentary_url`, and `is_discussion_url` fields

### Code Quality

- Fixed `not_nil!` usage in tests (replaced with `try` and `as(String)`)
- Fixed unused rescue variables in thread_safe_cache_spec
- Fixed useless variable assignment in thread_safe_cache_spec
- Resolved heredoc indentation issues in test files
- Added `.ameba.yml` configuration for lint exclusions
- All 199 tests passing

### Tests Added

- 6 new tests for `<comments>` element extraction in RSS feeds
- Tests cover both DOM and streaming parsers
- Tests cover fallback behavior and URL pattern detection

## [0.8.2] - 2026-03-26

### Added

- Structured configuration with composable sub-configs:
  - `TimeoutConfig` for connection/read timeouts
  - `RetryConfig` for retry behavior
  - `CircuitBreakerConfig` for circuit breaker settings
  - `RateLimitConfig` for rate limiting parameters
  - `StreamingConfig` for streaming parser options
  - `CacheConfig` for caching options
- `driver_detection_mode` option with modes: `Auto`, `ContentType`, `UrlOnly`, `ExplicitOnly`
  - `UrlOnly` mode skips HEAD requests for faster detection
- `error_detail_level` option with levels: `Minimal`, `Normal`, `Debug`
  - Controls verbosity of debug logging to prevent sensitive data leakage
- `max_concurrent_requests` option for request semaphore
  - Prevents resource exhaustion and deadlocks in high-volume scenarios
  - Uses Channel-based semaphore pattern for thread safety
- Deprecation warning for `http_client_pool_size` parameter (silently ignored)

### Changed

- `RequestConfig` refactored from record to class with backward-compatible constructors
- Consistent error handling across all `pull` method overloads
- Removed unreachable `CircuitOpenError` case from `handle_error`

### Backward Compatibility

- All existing flat-parameter constructors continue to work
- New structured configuration is optional
- No breaking changes to public API

## [0.8.1.1] - 2026-03-26

### Fixed

- Reddit URL assignment corrected:
  - `url` is now the external article URL (or Reddit permalink for self-posts)
  - `comment_url` is now the Reddit discussion URL
  - `is_discussion_url` is now `false` for Reddit entries (since `url` is not a discussion)

## [0.8.1] - 2026-03-26

### Added

- In-memory LRU cache for Reddit fetches with sort-specific TTL values
  - new/rising posts: 30 second TTL
  - hot posts: 2 minute TTL
  - top/controversial posts: 10 minute TTL
- `Fetcher::Cache` module for cache management (get, set, clear, stats)
- Cache statistics tracking (hits, misses, evictions, hit ratio)
- `Fetcher::CacheStats` struct for cache performance monitoring
- `cache_enabled`, `cache_max_size`, `cache_default_ttl` configuration options in RequestConfig
- Reddit posts now return both discussion URL (entry.url) and external URL (entry.comment_url)
- 22 new tests for cache functionality

### Changed

- Reddit link resolution now always returns discussion permalink as primary URL
- External link (for link posts) moved to `comment_url` field
- Cache disabled by default for non-Reddit fetchers

### Backward Compatibility

- All new fields have default values, existing code works unchanged
- Reddit entries now have additional `comment_url` field populated for link posts

## [0.8.0] - 2026-03-18

### Added

- `comment_url : String?` field to Entry - link to discussion thread
- `commentary_url : String?` field to Entry - link to publisher's commentary
- `is_discussion_url : Bool` field to Entry - true if main URL IS a discussion thread
- `LinkResolver` module for extracting comment/commentary links from feeds
- Support for `<link rel="replies">` and `<link rel="comments">` in RSS/Atom
- Support for `<link rel="related">` in Atom (Daring Fireball pattern)
- Automatic detection of discussion URLs by pattern (`/comments/`, `/item?id=`, `/s/`, etc.)

### Changed

- Reddit entries now have `is_discussion_url = true`

### Backward Compatibility

All new fields have default values (`nil` or `false`), so existing code works unchanged.

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

[0.9.4]: https://github.com/kritoke/fetcher.cr/compare/v0.9.3..v0.9.4
[0.9.3]: https://github.com/kritoke/fetcher.cr/compare/v0.9.2..v0.9.3
[0.9.0]: https://github.com/kritoke/fetcher.cr/compare/v0.8.3..v0.9.0
[0.8.3]: https://github.com/kritoke/fetcher.cr/compare/v0.8.2..v0.8.3
[0.8.2]: https://github.com/kritoke/fetcher.cr/compare/v0.8.1.1..v0.8.2
[0.8.1.1]: https://github.com/kritoke/fetcher.cr/compare/v0.8.1..v0.8.1.1
[0.8.1]: https://github.com/kritoke/fetcher.cr/compare/v0.8.0..v0.8.1
[0.8.0]: https://github.com/kritoke/fetcher.cr/compare/v0.7.0..v0.8.0
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
