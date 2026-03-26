## Design: In-Memory LRU Cache for Reddit

### Architecture Overview

The cache uses a cache-aside pattern:
1. Check cache for existing entry
2. If hit and fresh, return cached result
3. If miss or expired, fetch from Reddit API
4. Store result in cache on success
5. Return result

### Data Structures

```crystal
# Cache entry with metadata
struct CacheEntry(T)
  value : T
  timestamp : Time
  ttl : Time::Span
end

# LRU tracking via linked list + hash map
class Cache
  @data : Hash(String, CacheEntry)
  @access_order : Array(String)  # Most recent at end
  @mutex : Mutex
end
```

### Key Generation

```
fetcher:reddit:{subreddit}:{sort}:{limit}
```

Example:
- `fetcher:reddit:crystal:hot:25`
- `fetcher:reddit:news:top:10`

### TTL by Sort Type

| Sort | TTL | Rationale |
|------|-----|-----------|
| new | 30s | High churn, frequent updates |
| rising | 30s | High churn, frequent updates |
| hot | 2min | Moderate churn |
| top | 10min | Low churn, rankings change slowly |
| controversial | 10min | Low churn |

### Thread Safety

- Single Mutex protects all cache operations
- Fiber-safe via Mutex.synchronize
- LRU order updates are atomic

### Memory Management

- Maximum entries configurable (default: 1000)
- Eviction removes least recently used entry
- Entries track their own expiration

### Error Handling

- Corrupted cache entries treated as cache miss
- Network errors do not affect cache
- Cache errors fallback to direct fetch

### Configuration Options

```crystal
record RequestConfig
  # ... existing fields ...
  cache_enabled : Bool = true
  cache_max_size : Int32 = 1000
  cache_default_ttl : Time::Span = 5.minutes
end
```

### Cache Module API

```crystal
module Fetcher
  module Cache
    def self.get(url : String) : Result?
    def self.set(url : String, result : Result, ttl : Time::Span) : Nil
    def self.clear : Nil
    def self.clear_subreddit(subreddit : String) : Nil
    def self.stats : CacheStats
  end
  
  struct CacheStats
    hits : UInt64
    misses : UInt64
    evictions : UInt64
  end
end
```