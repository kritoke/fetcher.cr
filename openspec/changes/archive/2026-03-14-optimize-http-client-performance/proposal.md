## Why

The current HTTP client implementation suffers from performance bottlenecks including inefficient connection handling, fixed concurrency limits, blocking I/O operations, and lack of intelligent retry mechanisms. These issues cause resource exhaustion under load, slow response times, and poor scalability when fetching multiple feeds simultaneously.

## What Changes

- **HTTP Client Connection Pooling**: Create a shared client pool with configurable size and reuse connections across multiple fetch operations
- **Dynamic Concurrency Control**: Replace fixed semaphore with adaptive concurrency based on system resources, configurable via feeds.yml (e.g., max_concurrent_fetches: 16)
- **True Async/Await Pattern**: Use Crystal's async/await for non-blocking I/O operations and reduce fiber stack memory usage
- **Connection Timeout Optimization**: Separate connection timeout from read timeout and implement exponential backoff with jitter for retries
- **Batch Processing for Similar Domains**: Group feeds by domain to reduce DNS lookups and TLS handshakes, with domain-based rate limiting

## Capabilities

### New Capabilities
- `http-client-pooling`: Shared HTTP client connection pool with configurable size and connection reuse
- `dynamic-concurrency-control`: Adaptive concurrency management based on system resources with YAML configuration
- `async-http-fetching`: Non-blocking I/O operations using Crystal's async/await pattern
- `intelligent-timeout-retry`: Separate connection/read timeouts with exponential backoff and jitter
- `domain-batch-processing`: Domain-based feed grouping with rate limiting to optimize DNS and TLS overhead

### Modified Capabilities

## Impact

- Core HTTP fetching logic in src/ directory
- Configuration loading and parsing from feeds.yml
- Feed processing pipeline and scheduler
- Network resource management and error handling
- Memory usage patterns and fiber management