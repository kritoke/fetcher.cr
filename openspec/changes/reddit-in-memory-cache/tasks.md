## Implementation Tasks

### Phase 1: Core Cache Infrastructure

- [ ] Create `src/fetcher/cache.cr` with LRU cache implementation
  - [ ] Define `CacheEntry(T)` struct with value, timestamp, ttl
  - [ ] Implement `Cache` class with Hash + Array for LRU tracking
  - [ ] Add `get(key)` method with expiration check
  - [ ] Add `set(key, value, ttl)` method with LRU eviction
  - [ ] Add `clear` method
  - [ ] Add `clear_subreddit(subreddit)` method
  - [ ] Implement thread-safe operations with Mutex
  - [ ] Add statistics tracking (hits, misses, evictions)

### Phase 2: Configuration Extension

- [ ] Update `src/fetcher/request_config.cr`
  - [ ] Add `cache_enabled : Bool = true` field
  - [ ] Add `cache_max_size : Int32 = 1000` field
  - [ ] Add `cache_default_ttl : Time::Span = 5.minutes` field

### Phase 3: Reddit Integration

- [ ] Modify `src/fetcher/reddit.cr`
  - [ ] Add cache key generation helper
  - [ ] Add sort-specific TTL mapping
  - [ ] Integrate cache lookup in `pull` method
  - [ ] Store successful results in cache
  - [ ] Skip cache for RSS fallback responses
  - [ ] Skip cache for error responses

### Phase 4: Testing

- [ ] Create `spec/cache_spec.cr`
  - [ ] Test basic get/set operations
  - [ ] Test LRU eviction when max size exceeded
  - [ ] Test TTL expiration
  - [ ] Test thread safety with concurrent access
  - [ ] Test cache statistics tracking
  - [ ] Test clear and clear_subreddit

- [ ] Update existing specs if needed

### Phase 5: Validation

- [ ] Run full test suite
- [ ] Run crystal spec
- [ ] Run ameba linter if available
- [ ] Verify no regression in existing functionality

## Dependencies

None - this implementation uses only Crystal standard library:
- `Hash` for key-value storage
- `Array` for LRU ordering
- `Mutex` for thread safety
- `Time` for TTL calculations