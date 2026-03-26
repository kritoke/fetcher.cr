## Why

Reddit is frequently used with this library for fetching multiple feeds. However, the current implementation makes a new HTTP request every time, even when fetching the same subreddit/sort combination within short timeframes. This causes:

1. **Unnecessary API load**: Reddit's rate limits (60 requests/minute for unauthenticated) can be quickly exhausted
2. **Increased latency**: Network round-trips delay response delivery
3. **Redundant processing**: Parsing the same JSON repeatedly wastes CPU cycles
4. **Poor user experience**: Slow responses when rate limits are hit

Adding an in-memory LRU cache specifically optimized for Reddit will dramatically improve performance for repeated fetches while maintaining fresh data for dynamic content.

## What Changes

- **New Cache Module**: Add `src/fetcher/cache.cr` with thread-safe LRU implementation
- **Cache Configuration**: Extend `RequestConfig` with cache settings (enabled, max_size, default_ttl)
- **Reddit Integration**: Modify `Reddit.pull` to check/cache results
- **Sort-Specific TTL**: Apply different cache durations based on sort type (new=30s, hot=2min, top=10min)
- **Cache Statistics**: Track hits, misses, and evictions for monitoring
- **Cache Clear API**: Provide methods to clear cache when needed

## Capabilities

### New Capabilities
- `in-memory-reddit-cache`: LRU cache for Reddit feed results with configurable TTL
- `sort-specific-ttl`: Different cache durations based on Reddit sort type
- `cache-statistics`: Hit/miss tracking for cache performance monitoring
- `cache-control`: Enable/disable cache via configuration

### Modified Capabilities
- `reddit-fetching`: Reddit.pull to use cache-aside pattern
- `request-configuration`: RequestConfig extended with cache settings

## Impact

- **New Module**: `src/fetcher/cache.cr` - Thread-safe LRU cache implementation
- **Modified Modules**: `src/fetcher/reddit.cr`, `src/fetcher/request_config.cr`
- **Public API**: `RequestConfig` gains new optional fields; new `Cache` module methods
- **Dependencies**: No new external dependencies (zero-dependency library maintained)
- **Testing**: New spec for cache functionality; integration tests for Reddit caching
- **Performance**: Significant improvement for repeated Reddit fetches; reduced API load
- **Memory**: Minimal overhead (~few MB for typical cache sizes)