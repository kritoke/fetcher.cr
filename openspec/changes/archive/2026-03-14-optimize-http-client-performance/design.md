## Context

The current fetcher.cr implementation uses a simple HTTP client without connection pooling, fixed concurrency limits, and blocking I/O operations. This leads to performance bottlenecks when fetching multiple feeds simultaneously, causing resource exhaustion, slow response times, and poor scalability.

## Goals / Non-Goals

**Goals:**
- Implement HTTP client connection pooling to reuse connections and reduce overhead
- Replace fixed semaphore with dynamic concurrency control based on system resources
- Utilize Crystal's async/await for non-blocking I/O operations
- Optimize timeout handling with separate connection/read timeouts and intelligent retry logic
- Implement domain-based batch processing to reduce DNS and TLS overhead

**Non-Goals:**
- Complete rewrite of the entire HTTP layer
- Adding support for protocols other than HTTP/HTTPS
- Implementing complex caching mechanisms beyond connection reuse

## Decisions

**HTTP Client Pooling Implementation**
- Use Crystal's built-in HTTP::Client with connection pooling rather than external dependencies
- Implement a shared pool managed by a singleton or dependency injection pattern
- Pool size configurable via feeds.yml with reasonable defaults (10-20 connections)

**Dynamic Concurrency Control**
- Replace fixed semaphore with adaptive concurrency based on available system resources
- Monitor system memory and CPU usage to adjust concurrency limits dynamically
- Allow explicit configuration override via feeds.yml (max_concurrent_fetches)
- Default behavior scales with available cores and memory

**Async/Await Pattern**
- Leverage Crystal's native async/await support for non-blocking I/O
- Restructure feed fetching to use async methods throughout the pipeline
- Reduce fiber stack allocation by reusing fibers where possible
- Maintain backward compatibility with existing synchronous APIs

**Timeout and Retry Strategy**
- Separate connection timeout (typically shorter) from read timeout (longer)
- Implement exponential backoff with jitter for retry logic
- Maximum retry attempts configurable per feed/domain
- Include circuit breaker pattern to prevent cascading failures

**Domain Batch Processing**
- Group feeds by domain during scheduling phase
- Implement domain-specific rate limiting to prevent overwhelming individual servers
- Cache DNS lookups and TLS sessions per domain
- Process batches sequentially within domains but concurrently across domains

## Risks / Trade-offs

**[Risk] Increased complexity in error handling** → Implement comprehensive logging and monitoring to track async operations and connection states

**[Risk] Memory usage with large connection pools** → Set reasonable default limits and provide clear documentation for configuration

**[Risk] Compatibility issues with existing feeds.yml format** → Maintain backward compatibility by making new configuration options optional with sensible defaults

**[Risk] Performance regression during transition period** → Implement feature flags to enable/disable optimizations incrementally