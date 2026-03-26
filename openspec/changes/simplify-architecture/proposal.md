## Why

The fetcher.cr codebase has accumulated layers of over-engineering that increase maintenance burden without proportional value. Components like system resource monitoring (`/proc` file reading), duplicate streaming parsers, and complex adaptive concurrency control add ~600+ lines of code for problems most users don't have. Meanwhile, the library lacks a circuit breaker - a critical feature for production use cases involving thousands of feeds.

This change removes unnecessary complexity while adding production-critical features, making fetcher.cr a cleaner, more maintainable, and more robust library suitable as Crystal's defacto feed fetcher.

## What Changes

### Removals
- Delete `adaptive_concurrency_controller.cr` - system resource monitoring belongs in application code, not a library
- Delete `simple_json_streaming_parser.cr` - fake streaming (uses `JSON.parse`)
- Delete `working_json_streaming_parser.cr` - fake streaming (uses `gets_to_end`)
- Delete `simple_xml_streaming_parser.cr` - duplicate/unused
- Delete `connection_pool.cr` - unused, `CrestHttpClient` has its own client caching
- Delete orphaned test file `spec/adaptive_concurrency_controller_spec.cr`
- **BREAKING**: Remove all `*_async` methods (8 methods) - users can wrap in fibers with full control

### Simplifications
- Replace complex `ConcurrentFetcher` implementation with simple semaphore-based pattern (~30 lines vs ~270 lines)

### Additions
- Add `CircuitBreaker` class for per-domain failure tracking and automatic recovery
- Add circuit breaker configuration to `RequestConfig`

### Consolidations
- Keep ONE real JSON streaming parser (`json_streaming_parser.cr` with `JSON::PullParser`)
- Keep ONE XML streaming parser (`xml_streaming_parser.cr`)
- Continue using Crest for HTTP client with existing connection caching

## Capabilities

### New Capabilities
- `circuit-breaker`: Per-domain circuit breaker that tracks consecutive failures, opens circuit after threshold, and auto-recovers after cooldown period

### Modified Capabilities
- `concurrent-fetching`: Simplified implementation using semaphore pattern instead of adaptive concurrency control; same external behavior
- `rate-limiting`: Already implemented via token bucket in `CrestHttpClient`, no spec changes needed

## Impact

### Code Changes
- Remove ~500+ lines of dead/over-engineered code
- Add ~100 lines for circuit breaker
- Simplify `ConcurrentFetcher` from ~50 lines to ~30 lines
- Update `src/fetcher.cr` to remove deleted requires and async methods
- Update `RequestConfig` to add circuit breaker options

### API Changes
- **BREAKING**: Remove `pull_async`, `pull_rss_async`, `pull_reddit_async`, `pull_software_async`, `pull_json_feed_async` (and their overloaded variants)

### Dependencies
- No dependency changes (keep Crest and Sanitize)

### Documentation
- Update README to remove async API references
- Add circuit breaker usage documentation
- Document recommended async pattern (fiber + channel) for users who need async
