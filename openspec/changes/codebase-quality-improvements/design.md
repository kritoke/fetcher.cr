# Design: Codebase Quality Improvements

## Context

The fetcher.cr library is a Crystal feed fetching library supporting RSS, Atom, JSON Feed, Reddit, YouTube, and software releases. A comprehensive code review identified issues across security, performance, readability, and maintainability that need to be addressed while maintaining Crystal 1.18.2 compatibility.

### Current State
- Error handling uses inconsistent patterns (some return Result, some raise exceptions)
- Streaming parsers claim to be lazy but load all content into memory
- Global mutable state in rate limiters and circuit breakers
- Magic numbers and hardcoded values scattered throughout
- Duplicate code in GitLab/Codeberg providers (~80% overlap)
- Debug output via `puts` statements

### Constraints
- Must maintain Crystal 1.18.2 compatibility (no `Time.instant`)
- No breaking changes to public API
- Must preserve existing test coverage

## Goals / Non-Goals

**Goals:**
1. Fix security issues (error message mismatch, debug output, limit validation)
2. Optimize performance (streaming, string building, regex caching)
3. Improve readability (reduce nesting, centralize config, standardize errors)
4. Enhance maintainability (deduplicate code, add cleanup methods, proper logging)

**Non-Goals:**
- Refactoring the entire module structure
- Adding new features or capabilities
- Changing the public API signature
- Migrating to a different HTTP client library

## Decisions

### D1: Centralized Configuration Module

**Decision:** Create a `Fetcher::Config` module with all default values as constants.

**Rationale:**
- Current state: Defaults scattered across `request_config.cr`, `retry.cr`, `crest_http_client.cr`
- Centralization makes it easier to understand and modify defaults
- Single source of truth reduces risk of inconsistency

**Alternative Considered:** Keep defaults inline with their usage.
- Rejected: Harder to maintain, requires hunting through multiple files

```crystal
module Fetcher
  module Config
    MAX_FEED_SIZE = 10 * 1024 * 1024  # 10MB
    MAX_LIMIT = 1000
    DEFAULT_LIMIT = 100
    
    # Timeouts
    DEFAULT_CONNECT_TIMEOUT = 10.seconds
    DEFAULT_READ_TIMEOUT = 30.seconds
    
    # Circuit Breaker
    DEFAULT_CIRCUIT_BREAKER_THRESHOLD = 5
    DEFAULT_CIRCUIT_BREAKER_TIMEOUT = 60.seconds
    
    # Rate Limiting
    DEFAULT_RATE_LIMIT_CAPACITY = 10.0
    DEFAULT_RATE_LIMIT_REFILL_RATE = 1.0
    
    # Retry
    DEFAULT_MAX_RETRIES = 3
    DEFAULT_BASE_DELAY = 1.second
    DEFAULT_MAX_DELAY = 30.seconds
    DEFAULT_EXPONENTIAL_BASE = 2.0
    
    # Concurrency
    DEFAULT_MAX_CONCURRENT = 16
  end
end
```

### D2: Proper Exception Hierarchy

**Decision:** Add `ResponseTooLargeError` exception and fix `DNSError` misuse.

**Rationale:**
- Current code raises `DNSError` for response size errors (misleading)
- Proper exception types enable better error handling by consumers
- Maintains backward compatibility by keeping existing exceptions

```crystal
class ResponseTooLargeError < FetchError
  getter size : Int64
  getter max_size : Int64
  
  def initialize(@size : Int64, @max_size : Int64)
    super("Response too large: #{@size} bytes (max: #{@max_size})")
  end
end
```

### D3: Logging Infrastructure

**Decision:** Replace `puts` debug statements with Crystal's `Log` module.

**Rationale:**
- `puts` cannot be filtered or disabled at runtime
- `Log` module provides structured logging with levels
- Log messages can include context without string interpolation overhead

**Alternative Considered:** Keep `puts` with ENV flag.
- Rejected: Less flexible, no log levels, no structured output

```crystal
Log = ::Log.for("fetcher")

# Usage:
Log.debug { "Pulling URL #{url} with driver #{driver}" }
```

### D4: True Streaming Implementation

**Decision:** Rewrite streaming parsers to use incremental parsing.

**Rationale:**
- Current `XMLStreamingIterator` and `JSONStreamingIterator` load all entries on first `next` call
- True streaming reduces memory usage for large feeds
- Maintains Iterator interface for compatibility

**Implementation Approach:**
- Track parser state and position
- Parse one entry at a time in `next_entry`
- Remove `@entries` cache variable

### D5: String::Builder for Hot Paths

**Decision:** Replace string concatenation (`+=`) with `String::Builder`.

**Rationale:**
- String concatenation creates new string objects on each operation
- `String::Builder` uses internal buffer, more efficient for multiple appends
- Hot path: `read_text_content` in streaming parser

```crystal
private def read_text_content(reader : XML::Reader) : String
  builder = String::Builder.new
  while reader.read
    case reader.node_type
    when .text?, .cdata?
      builder << reader.value
    # ...
  end
  builder.to_s
end
```

### D6: Regex Pattern Caching

**Decision:** Pre-compile regex patterns as constants.

**Rationale:**
- Regex compilation is expensive
- Patterns like URL detection are called frequently
- Constants are compiled once at program start

```crystal
module Fetcher
  REDDIT_URL_PATTERN = %r{://(www\.)?reddit\.com/r/}i
  GITHUB_RELEASES_PATTERN = %r{://(www\.)?github\.com/[^/]+/[^/]+/releases}i
  GITLAB_RELEASES_PATTERN = %r{https?://([^/]+)/([^/]+/[^/]+)/-/releases}
  CODEBERG_RELEASES_PATTERN = %r{://(www\.)?codeberg\.org/[^/]+/[^/]+/releases}i
  YOUTUBE_CHANNEL_PATTERN = %r{://(www\.)?youtube\.com/channel/}i
end
```

### D7: Error Handling Standardization

**Decision:** Create shared `ErrorHandler` module for HTTP response handling.

**Rationale:**
- Each module (RSS, JSONFeed, Reddit, Software) has similar error handling
- DRY principle - extract common pattern
- Easier to maintain consistent behavior

```crystal
module Fetcher
  module ErrorHandler
    def self.handle_http_error(response, url : String) : Nil
      case response.status_code
      when 429
        raise RateLimitError.new(Error.rate_limited("Rate limited", url))
      when 500..599
        raise HTTPServerError.new(Error.server_error(response.status_code, nil, url))
      else
        raise HTTPError.new(Error.http(response.status_code, nil, url))
      end
    end
    
    def self.wrap_network_errors(url : String, &block)
      yield
    rescue ex : IO::TimeoutError
      raise TimeoutError.new(Error.timeout(ex.message || "Timeout", url))
    rescue ex : CrestHttpClient::DNSError
      raise DNSError.new(Error.dns(ex.message || "DNS error", url))
    rescue ex : FetchError
      raise ex
    end
  end
end
```

### D8: Provider Code Deduplication

**Decision:** Extract common GitLab/Codeberg pattern into shared methods.

**Rationale:**
- Both use same API structure (projects/:id/releases)
- Both fallback to Atom feeds
- Only difference is base URL and some field names

**Implementation:**
- Create `try_forge_api` and `try_forge_atom` methods
- Pass provider-specific parameters as arguments

### D9: Global State Cleanup

**Decision:** Add cleanup methods to rate limiter and circuit breaker registries.

**Rationale:**
- Global state persists across tests, causing test pollution
- No way to reset state between tests
- Cleanup methods enable proper test isolation

```crystal
module CrestHttpClient
  def self.reset_rate_limiters : Nil
    @@limiters_lock.synchronize { @@token_bucket_limiters.clear }
  end
end

module CircuitBreaker::Registry
  # Already has clear method - ensure it's used in tests
end
```

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| True streaming may be slower for small feeds | Keep DOM parser as default, streaming as opt-in |
| Log module requires Crystal 0.36+ | Crystal 1.18.2 includes Log module |
| Regex caching uses memory | Memory impact is negligible (few patterns) |
| Code deduplication may reduce flexibility | Keep provider-specific overrides available |
| Error handler changes may affect error messages | Maintain existing message format |

## Migration Plan

1. **Phase 1: Low-Risk Changes** (No behavior changes)
   - Add `Config` module with constants
   - Add `ResponseTooLargeError` exception
   - Add regex pattern constants
   - Add cleanup methods

2. **Phase 2: Internal Improvements** (Minor behavior changes)
   - Replace `puts` with `Log`
   - Use `String::Builder`
   - Add limit bounds validation

3. **Phase 3: Structural Changes** (Refactoring)
   - Extract error handling module
   - Deduplicate provider code
   - Fix streaming implementation

### Rollback Strategy
- Each phase is independently deployable
- Git tags at each phase for easy rollback
- Feature flags for streaming changes (use `config.use_streaming_parser`)

## Open Questions

1. Should `Log` be configured with a default level, or left to the consumer?
   - **Resolution**: Leave to consumer, document recommended configuration

2. Should the true streaming implementation be the default?
   - **Resolution**: Keep DOM as default, streaming opt-in via config flag
