# Feed Fetcher Standard

## 1. Content-Type Based Detection
- **Requirement**: Replace URL regex detection with HTTP content-type sniffing 
- **Implementation**: 
  - Send HEAD request to get `Content-Type` header
  - Fall back to extension-based detection only when needed
  - Maintain backward compatibility with existing drivers
- **Validation**: All test fixtures must be correctly identified by content-type

## 2. Unified HTTP Client
- **Requirement**: Single HTTP client implementation with full configuration support
- **Implementation**:
  - Centralized `HTTPClient` class handling all requests
  - Support for timeouts, headers, compression, and retries
  - Proper connection pooling and resource management
- **Validation**: All drivers must use the same HTTP client instance

## 3. Structured Error Handling  
- **Requirement**: Typed exception hierarchy with clear error categories
- **Implementation**:
  - `Fetcher::Error` base class with subclasses:
    - `HTTPError` (status codes)
    - `ParsingError` (format issues) 
    - `ValidationError` (URL/feed structure)
    - `TransientError` (network issues)
  - Preserve original exception context
- **Validation**: All error paths must return typed exceptions

## 4. Standard URL Validation
- **Requirement**: Use established validation libraries instead of custom IP checks
- **Implementation**:
  - Replace `HTMLUtils.validate_url` with `URI` standard library
  - Add proper IPv4/IPv6 validation using `Socket::IPAddress`
  - Block private IPs using system network APIs
- **Validation**: Pass OWASP URL validation test suite

## 5. Separated Concerns
- **Requirement**: Clear separation between parsing, validation, and creation
- **Implementation**:
  - `EntryParser` interface with driver-specific implementations
  - `EntryFactory` for creating validated entries
  - `ResultBuilder` for structured result construction
- **Validation**: Zero direct calls to `Entry.create` outside factory

## 6. Comprehensive Testing
- **Requirement**: Real integration tests with canonical feed examples
- **Implementation**:
  - Test fixtures from real-world feeds (RSS/Atom/JSON/Reddit/GitHub)
  - Integration tests hitting actual endpoints (with caching)
  - Property-based testing for edge cases
- **Validation**: 95%+ coverage on parsing logic

## 7. Token Bucket Rate Limiting
- **Requirement**: Scalable rate limiting supporting complex scenarios  
- **Implementation**:
  - Replace global mutex hash with token bucket algorithm
  - Support per-domain and global rate limits
  - Configurable burst capacity and refill rates
- **Validation**: Handle 1000+ concurrent requests without starvation

## 8. Standard Time Parsing
- **Requirement**: Use RFC-compliant time parsing
- **Implementation**:
  - Replace custom format lists with `Time.parse_rfc3339`
  - Fallback to lenient parsing only when necessary
  - Preserve timezone information properly
- **Validation**: Parse all valid RFC3339/RFC2822 dates correctly

## 9. Streaming Processing
- **Requirement**: Memory-safe feed processing with streaming
- **Implementation**:  
  - Stream parsing for XML/JSON feeds
  - Hard memory limits (10MB) with compression awareness
  - Early termination on size violations
- **Validation**: Process 100MB feeds without OOM errors

## 10. Consistent Configuration
- **Requirement**: Unified configuration across all components
- **Implementation**:
  - Single `FetcherConfig` passed through entire call chain
  - Immutable configuration objects
  - Default configuration with explicit overrides
- **Validation**: All timeout/retry settings honored consistently