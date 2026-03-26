# In-Memory Cache for Reddit Fetches Specification

## ADDED Requirements

### Requirement: In-memory LRU cache for Reddit fetches
The system SHALL provide a thread-safe, in-memory LRU cache specifically optimized for Reddit feed caching.

#### Scenario: Cache hit returns cached result
- **WHEN** a Reddit fetch request is made for a cached subreddit/sort/limit combination
- **AND** the cache entry is not expired
- **THEN** the system SHALL return the cached Result without making an HTTP request
- **AND** the cache entry access time SHALL be updated for LRU ordering

#### Scenario: Cache miss triggers fetch
- **WHEN** a Reddit fetch request is made for a non-cached or expired entry
- **THEN** the system SHALL fetch from the Reddit API
- **AND** it SHALL store the result in the cache on successful fetch
- **AND** it SHALL return the fresh result

#### Scenario: Cache entry expiration
- **WHEN** a cache entry exceeds its TTL
- **THEN** the system SHALL treat the entry as a cache miss
- **AND** it SHALL fetch fresh data from the Reddit API

### Requirement: Configurable cache settings
The system SHALL allow cache behavior to be configured via RequestConfig.

#### Scenario: Default cache behavior
- **WHEN** cache_enabled is not configured or set to true
- **THEN** the system SHALL use the default cache settings
- **AND** it SHALL use a default max size of 1000 entries
- **AND** it SHALL use a default TTL of 5 minutes

#### Scenario: Disable cache
- **WHEN** cache_enabled is set to false in RequestConfig
- **THEN** the system SHALL bypass the cache entirely
- **AND** it SHALL always fetch fresh data from the Reddit API

#### Scenario: Custom cache size
- **WHEN** cache_max_size is configured with a specific value
- **THEN** the system SHALL limit the cache to that many entries
- **AND** it SHALL evict the least recently used entry when the limit is exceeded

#### Scenario: Custom default TTL
- **WHEN** cache_default_ttl is configured with a specific duration
- **THEN** the system SHALL use that TTL for new cache entries
- **AND** it SHALL apply it unless overridden by sort-specific TTL

### Requirement: Sort-specific TTL values
The system SHALL apply different TTL values based on the sort type.

#### Scenario: New posts have short TTL
- **WHEN** fetching Reddit posts with sort=new or sort=rising
- **THEN** the system SHALL use a TTL of 30-60 seconds
- **AND** fresh data SHALL be fetched frequently due to high churn

#### Scenario: Hot posts have medium TTL
- **WHEN** fetching Reddit posts with sort=hot
- **THEN** the system SHALL use a TTL of 2-5 minutes
- **AND** the content remains relatively fresh

#### Scenario: Top/controversial posts have longer TTL
- **WHEN** fetching Reddit posts with sort=top or sort=controversial
- **THEN** the system SHALL use a TTL of 10-15 minutes
- **AND** these posts change infrequently

### Requirement: Thread-safe cache operations
The system SHALL ensure cache operations are safe for concurrent access.

#### Scenario: Concurrent cache access
- **WHEN** multiple fibers access the cache simultaneously
- **THEN** the system SHALL use proper synchronization
- **AND** it SHALL prevent race conditions during read/write operations
- **AND** it SHALL maintain LRU ordering correctly

#### Scenario: Concurrent cache eviction
- **WHEN** multiple fibers trigger eviction simultaneously
- **THEN** the system SHALL safely remove the oldest entry
- **AND** it SHALL not corrupt the cache structure

### Requirement: Graceful cache failure handling
The system SHALL handle cache errors gracefully without affecting fetch operations.

#### Scenario: Cache corruption
- **WHEN** a cached entry is corrupted or unparseable
- **THEN** the system SHALL treat it as a cache miss
- **AND** it SHALL fetch fresh data from the Reddit API

#### Scenario: Memory pressure
- **WHEN** the system is under memory pressure
- **THEN** the cache SHALL automatically evict old entries
- **AND** it SHALL continue to function without errors

### Requirement: Cache key generation
The system SHALL generate consistent cache keys for Reddit requests.

#### Scenario: Key includes all request parameters
- **WHEN** generating a cache key for a Reddit request
- **THEN** the key SHALL include subreddit name
- **AND** the key SHALL include sort type (hot, new, top, rising)
- **AND** the key SHALL include the limit parameter

#### Scenario: Same request produces same key
- **WHEN** two requests have identical parameters (subreddit, sort, limit)
- **THEN** they SHALL produce the same cache key
- **AND** the second request SHALL return the cached result

### Requirement: Cache statistics tracking
The system SHALL track cache performance statistics.

#### Scenario: Track cache hits
- **WHEN** a cache hit occurs
- **THEN** the system SHALL increment the hit counter
- **AND** the statistic SHALL be available for monitoring

#### Scenario: Track cache misses
- **WHEN** a cache miss occurs
- **THEN** the system SHALL increment the miss counter
- **AND** the statistic SHALL be available for monitoring

#### Scenario: Cache hit ratio calculation
- **WHEN** cache statistics are queried
- **THEN** the system SHALL provide hit ratio calculation
- **AND** it SHALL report total hits and misses

### Requirement: Clear cache functionality
The system SHALL provide a way to clear the cache.

#### Scenario: Clear all cache entries
- **WHEN** Cache.clear is called
- **THEN** the system SHALL remove all entries from the cache
- **AND** the cache statistics SHALL be reset

#### Scenario: Clear specific subreddit cache
- **WHEN** Cache.clear_subreddit(subreddit) is called
- **THEN** the system SHALL remove all cache entries for that subreddit
- **AND** entries for other subreddits SHALL remain

### Requirement: Cache integration with existing Reddit flow
The cache SHALL integrate seamlessly with existing Reddit fetch logic.

#### Scenario: Cache used in Reddit.pull
- **WHEN** Fetcher.pull is called with a Reddit URL
- **AND** cache is enabled
- **THEN** the system SHALL check the cache first
- **AND** it SHALL use the cache result if available and fresh

#### Scenario: Fallback to RSS when JSON API fails
- **WHEN** the Reddit JSON API fails and fallback to RSS occurs
- **THEN** the cache SHALL NOT cache the RSS fallback result
- **AND** it SHALL only cache successful JSON API responses

#### Scenario: Cache respects error responses
- **WHEN** a fetch results in an error (rate limited, server error, etc.)
- **THEN** the system SHALL NOT cache the error response
- **AND** subsequent requests SHALL attempt fresh fetches
