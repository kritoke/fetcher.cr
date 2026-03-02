# Fetcher.cr - Unimplemented Features & Future Enhancements

## Specification ID: SPEC-003
## Status: Planning Phase
## Priority: Medium
## Created: 2026-03-01
## Depends On: SPEC-002 (Priority 3 Features)

---

## Overview

This specification tracks unimplemented features and future enhancements identified during the Priority 3 implementation and code review. These features were either planned but not implemented, or discovered as gaps during development.

---

## Phase 4B: Complete RequestConfig Implementation

### 4B.1 Redirect Control

**Status:** ⏳ UNIMPLEMENTED  
**Priority:** Medium  
**Complexity:** Low

**Problem:**
`RequestConfig.max_redirects` and `RequestConfig.follow_redirects` fields exist but are not used because Crystal's `HTTP::Client` doesn't expose these settings in the current version.

**Current Code:**
```crystal
# src/fetcher/request_config.cr
record RequestConfig,
  connect_timeout : Time::Span = 10.seconds,
  read_timeout : Time::Span = 30.seconds,
  max_redirects : Int32 = 5,        # ❌ Not implemented
  follow_redirects : Bool = true,    # ❌ Not implemented
  ssl_verify : Bool = true           # ❌ Not implemented
```

**Implementation Options:**

#### Option A: Manual Redirect Handling (Recommended)
```crystal
module Fetcher
  module HTTPClient
    def self.fetch(url : String, headers : HTTP::Headers, config : RequestConfig = RequestConfig.new) : HTTP::Client::Response
      uri = URI.parse(url)
      client = HTTP::Client.new(uri)
      client.connect_timeout = config.connect_timeout
      client.read_timeout = config.read_timeout
      
      response = client.get(uri.request_target, headers: headers)
      
      # Manual redirect handling if follow_redirects is false
      if !config.follow_redirects && [301, 302, 303, 307, 308].includes?(response.status_code)
        return response  # Return redirect response without following
      end
      
      # Could implement custom redirect following with max_redirects limit
      response
    end
  end
end
```

**Benefits:**
- Full control over redirect behavior
- Can prevent redirect loops
- Can log/audit redirects

**Drawbacks:**
- More complex code
- Need to handle redirect logic manually

#### Option B: Remove Unused Fields
```crystal
record RequestConfig,
  connect_timeout : Time::Span = 10.seconds,
  read_timeout : Time::Span = 30.seconds
```

**Benefits:**
- Cleaner API
- No confusion about supported features

**Drawbacks:**
- May need to re-add when Crystal supports it

**Recommendation:** Option A - Implement manual redirect control for production use.

---

### 4B.2 SSL Verification Control

**Status:** ⏳ UNIMPLEMENTED  
**Priority:** Low (Security Concern)  
**Complexity:** Medium

**Problem:**
`RequestConfig.ssl_verify` field exists but is not implemented.

**Use Case:**
- Development/testing with self-signed certificates
- Internal services with custom CA

**Implementation:**
```crystal
module Fetcher
  module HTTPClient
    def self.fetch(url : String, headers : HTTP::Headers, config : RequestConfig = RequestConfig.new) : HTTP::Client::Response
      uri = URI.parse(url)
      
      # Configure TLS if HTTPS
      tls = nil
      if uri.scheme == "https"
        tls = OpenSSL::SSL::Context::Client.new
        tls.verify_mode = config.ssl_verify ? OpenSSL::SSL::VerifyMode::PEER : OpenSSL::SSL::VerifyMode::NONE
        
        # WARNING: Disabling verification is insecure!
        # Should only be used in development/testing
      end
      
      client = HTTP::Client.new(uri, tls: tls)
      # ... rest of implementation
    end
  end
end
```

**Security Warning:**
⚠️ **Disabling SSL verification is dangerous and should only be done in controlled environments!**

**Recommendation:**
- Implement with strong warnings in documentation
- Consider requiring explicit opt-in for disabling verification
- Add runtime warnings when ssl_verify is false

---

## Phase 5: Error Categorization

**Status:** ⏳ UNIMPLEMENTED  
**Priority:** Medium  
**Complexity:** Medium

**See:** SPEC-002 Phase 5 for full details

### 5.1 ErrorType Enum

**Planned Implementation:**
```crystal
module Fetcher
  enum ErrorType
    NetworkError        # DNS, connection, timeout
    HTTPError           # 4xx, 5xx status codes
    ParseError          # Invalid XML/JSON
    NotFoundError       # 404
    RateLimited         # 429
    ServerError         # 5xx
    AuthenticationError # 401, 403
    UnsupportedFormat   # Unknown feed format
  end
  
  record Result,
    # ... existing fields ...
    error_type : ErrorType? = nil,
    error_code : Int32? = nil
end
```

### 5.2 Implementation Plan

1. Add `ErrorType` enum to `src/fetcher/error_type.cr`
2. Update `Result` record to include `error_type` and `error_code`
3. Update all error paths to set appropriate error types
4. Update error handling in retry logic
5. Add tests for each error type

### 5.3 Benefits

- Programmatic error handling
- Better observability/monitoring
- Clearer error messages to users
- Easier debugging

---

## Phase 6: Performance Optimizations

### 6.1 Connection Pooling

**Status:** ⏳ DEFERRED (was in v0.1, removed in v0.2)  
**Priority:** Medium  
**Complexity:** High

**Background:**
v0.1 had `HTTPClientPool` for client reuse. v0.2 removed it for simplicity.

**When to Re-implement:**
- User feedback indicates performance issues
- High-frequency fetching use cases emerge
- Before v1.0 production release

**Implementation Approach:**
```crystal
module Fetcher
  class ClientPool
    def initialize(size : Int32 = 5)
      @pool = Channel(HTTP::Client).new(size)
      size.times { @pool.send(create_client) }
    end
    
    def checkout(&block : HTTP::Client -> T) : T
      client = @pool.receive
      begin
        yield client
      ensure
        @pool.send(client)
      end
    end
  end
end
```

---

### 6.2 Response Caching

**Status:** ❓ PROPOSED  
**Priority:** Low  
**Complexity:** Medium

**Idea:**
Cache feed responses in-memory or with Redis/Memcached for high-traffic scenarios.

**API:**
```crystal
config = Fetcher::RequestConfig.new(
  cache_ttl: 5.minutes,
  cache_backend: "redis"  # or "memory"
)
result = Fetcher.pull("https://example.com/feed.xml", config: config)
```

---

## Phase 7: Additional Feed Format Support

### 7.1 RSS 1.0/RDF Enhancement

**Status:** ✅ PARTIAL (basic support exists)  
**Priority:** Low

**Current:**
- Detects RDF root element
- Extracts items

**Enhancements:**
- Better namespace handling
- RSS 1.0 module support (content, dc, sy)

---

### 7.2 Media RSS Support

**Status:** ❓ PROPOSED  
**Priority:** Low  
**Complexity:** Medium

**Idea:**
Extract media:content, media:thumbnail, media:description from RSS feeds.

**Use Case:**
- Video podcasts
- Image galleries
- Rich media content

---

## Phase 8: Developer Experience

### 8.1 Logging Hooks

**Status:** ❓ PROPOSED  
**Priority:** Low  
**Complexity:** Low

**Idea:**
Allow users to inject logging callbacks for debugging.

**API:**
```crystal
Fetcher.configure do |config|
  config.logger = ->(message : String) { puts "[Fetcher] #{message}" }
end
```

---

### 8.2 Request/Response Hooks

**Status:** ❓ PROPOSED  
**Priority:** Low  
**Complexity:** Medium

**Idea:**
Allow middleware-style hooks for custom processing.

**API:**
```crystal
Fetcher.configure do |config|
  config.before_request = ->(url : String, headers : HTTP::Headers) {
    # Modify headers, log, etc.
  }
  
  config.after_response = ->(response : HTTP::Client::Response) {
    # Log response, metrics, etc.
  }
end
```

---

## Implementation Priority

| Phase | Feature | Priority | Effort | Target Version |
|-------|---------|----------|--------|----------------|
| 4B.1 | Redirect Control | Medium | Low | v0.3.1 |
| 4B.2 | SSL Verification | Low | Medium | v0.4.0 |
| 5 | Error Categorization | Medium | Medium | v0.4.0 |
| 6.1 | Connection Pooling | Medium | High | v0.5.0 |
| 6.2 | Response Caching | Low | Medium | v0.5.0 |
| 7.1 | RSS 1.0 Enhancement | Low | Low | v0.4.0 |
| 7.2 | Media RSS | Low | Medium | v0.5.0 |
| 8.1 | Logging Hooks | Low | Low | v0.4.0 |
| 8.2 | Request/Response Hooks | Low | Medium | v0.5.0 |

---

## Recommendations

### Immediate (v0.3.1 patch):
1. **Fix RequestConfig** - Remove or implement unused fields
2. **Add documentation** - Clarify which features are implemented vs. planned

### Short-term (v0.4.0):
1. **Error Categorization** - Most requested feature
2. **Redirect Control** - Important for some use cases
3. **Logging Hooks** - Improves developer experience

### Long-term (v0.5.0+):
1. **Connection Pooling** - Performance optimization
2. **Response Caching** - Advanced feature
3. **Media RSS** - Niche use case

---

## References

- [SPEC-002](SPEC-002-priority-3-features.md) - Priority 3 Features
- [Crystal HTTP::Client Docs](https://crystal-lang.org/api/latest/HTTP/Client.html)
- [OpenSSL::SSL::Context](https://crystal-lang.org/api/latest/OpenSSL/SSL/Context.html)
- [RSS 1.0 Spec](http://web.resource.org/rss/1.0/)
- [Media RSS Spec](https://www.rssboard.org/media-rss)

---

## Sign-off

**Created:** 2026-03-01  
**Author:** Code Review  
**Status:** Ready for Planning  
**Next Review:** After v0.3.0 release
