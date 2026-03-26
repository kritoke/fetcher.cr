## Context

fetcher.cr is a Crystal library for fetching RSS feeds, Reddit posts, JSON Feeds, and software releases. It has accumulated complexity over time:

- **AdaptiveConcurrencyController** (224 lines): Reads `/proc/meminfo` and `/proc/stat` to dynamically adjust concurrency based on system resources
- **Multiple JSON streaming parsers**: 3 implementations where only 1 actually streams
- **ConnectionPool module** (83 lines): Unused - `CrestHttpClient` has its own client caching
- **8 async methods**: Return `Channel(Result)` but add API surface and resource leak potential

The target use case is fetching thousands of feeds every 10-30 minutes, which requires:
- Per-domain rate limiting (already implemented via token bucket)
- Circuit breakers (missing)
- Memory safety via streaming (partially implemented)

## Goals / Non-Goals

**Goals:**
- Remove ~500+ lines of unnecessary complexity
- Add circuit breaker for production robustness
- Consolidate to ONE real streaming parser per format (XML, JSON)
- Simplify `ConcurrentFetcher` to semaphore-based pattern
- Maintain backward compatibility for non-async APIs

**Non-Goals:**
- Connection pooling changes (keep existing Crest-based client caching)
- Changes to rate limiting (token bucket implementation is appropriate)
- Changes to URL validation (SSRF protection is good)
- Adding new feed format support

## Decisions

### D1: Remove AdaptiveConcurrencyController
**Decision**: Delete entirely, replace with simple semaphore in ConcurrentFetcher.

**Rationale**: 
- Reading `/proc` files is inappropriate for a library - it's infrastructure monitoring, not fetcher logic
- The dynamic adjustment based on memory/CPU couples the library to Linux and specific deployment contexts
- A simple semaphore provides the same concurrency limiting without system coupling

**Alternatives considered**:
- Keep but disable by default: Still adds maintenance burden for rarely-used feature
- Make it optional via config: Adds complexity, users can implement at app level

### D2: Delete Fake Streaming Parsers
**Decision**: Delete `simple_json_streaming_parser.cr`, `working_json_streaming_parser.cr`, and `simple_xml_streaming_parser.cr` (if exists).

**Rationale**:
- These parsers load entire content into memory (`JSON.parse`, `gets_to_end`) - they're not streaming
- Having multiple "streaming" parsers with different behaviors is confusing
- The real streaming parser (`json_streaming_parser.cr` with `JSON::PullParser`) is the correct implementation

### D3: Remove Async API Methods
**Decision**: Delete all 8 `*_async` methods.

**Rationale**:
- Users can easily wrap synchronous calls in fibers: `spawn { channel << Fetcher.pull(url) }`
- Async methods create resource leak potential (unreceived channels)
- Doubles API surface for marginal convenience
- No cancellation or timeout support in current implementation

**Migration path for users**:
```crystal
# Before
channel = Fetcher.pull_async(url)
result = channel.receive

# After
channel = Channel(Fetcher::Result).new
spawn { channel << Fetcher.pull(url) }
result = channel.receive
```

### D4: Add Circuit Breaker
**Decision**: Implement per-domain circuit breaker with configurable thresholds.

**Design**:
```crystal
class CircuitBreaker
  enum State
    Closed   # Normal operation
    Open     # Failing, reject all requests
    HalfOpen # Testing if recovered
  end
  
  @failure_count : Int32 = 0
  @last_failure_time : Time? = nil
  @state : State = State::Closed
  
  def record_success : Nil
  def record_failure : Nil
  def allow_request? : Bool
end

# Per-domain registry
@@circuit_breakers = Hash(String, CircuitBreaker).new
```

**Configuration** (add to `RequestConfig`):
- `circuit_breaker_failure_threshold: Int32 = 5` - failures before opening
- `circuit_breaker_cooldown: Time::Span = 30.seconds` - time before retry
- `circuit_breaker_enabled: Bool = true` - can disable per-request

### D5: Keep Connection Management in CrestHttpClient
**Decision**: Delete unused `connection_pool.cr`, keep client caching in `CrestHttpClient`.

**Rationale**:
- `CrestHttpClient` already has `@@http_clients` hash for per-host client reuse
- `ConnectionPool` module is never called
- Crest handles keep-alive internally

### D6: Simplified ConcurrentFetcher
**Decision**: Replace complex implementation with semaphore pattern.

**New implementation** (~30 lines):
```crystal
class ConcurrentFetcher
  DEFAULT_MAX_CONCURRENT = 16
  
  def self.pull_multiple(
    urls : Array(String),
    headers : HTTP::Headers = HTTP::Headers.new,
    limit : Int32 = 100,
    max_concurrent : Int32 = DEFAULT_MAX_CONCURRENT,
    config : RequestConfig = RequestConfig.new
  ) : Array(Result)
    semaphore = Channel(Nil).new(max_concurrent)
    results = Channel(Result).new
    
    urls.each do |url|
      spawn do
        semaphore.send(nil)
        begin
          results << Fetcher.pull(url, headers, limit, config)
        rescue ex
          results << Fetcher.error_result(ErrorKind::Unknown, ex.message)
        ensure
          semaphore.receive rescue nil
        end
      end
    end
    
    urls.size.times { results.receive }
  end
end
```

## Risks / Trade-offs

### Risk: Breaking change for async API users
**Mitigation**: 
- Clear deprecation notice in CHANGELOG
- Document migration path in README
- This is pre-1.0 (API unstable per README)

### Risk: Circuit breaker might block legitimate requests during temporary outages
**Mitigation**:
- Configurable thresholds and cooldown
- Can be disabled per-request
- Half-open state allows recovery testing

### Risk: Removed complexity might be needed by some users
**Mitigation**:
- All removed features can be implemented at application level
- System monitoring should be in monitoring infrastructure, not fetcher library
- Document patterns for users who need advanced features

## Migration Plan

1. **Version bump**: 0.6.4 → 0.7.0 (breaking changes)
2. **CHANGELOG entry**: List all breaking changes with migration paths
3. **README update**: Remove async API docs, add circuit breaker docs, add async pattern example
4. **No data migration**: Library has no persistent state

**Rollback**: Users can pin to 0.6.4 if they need removed features.

## Open Questions

None - all decisions are finalized based on prior discussion.
