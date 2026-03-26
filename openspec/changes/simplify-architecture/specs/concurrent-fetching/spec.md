## MODIFIED Requirements

### Requirement: Concurrent fetching uses semaphore-based concurrency control
The system SHALL use a simple semaphore pattern to limit concurrent requests, replacing the previous adaptive concurrency controller that monitored system resources.

#### Scenario: Concurrency limit respected
- **GIVEN** `max_concurrent: 5`
- **WHEN** 10 URLs are fetched concurrently via `ConcurrentFetcher.pull_multiple`
- **THEN** at most 5 requests are in-flight simultaneously

#### Scenario: All results returned
- **GIVEN** 10 URLs to fetch
- **WHEN** `ConcurrentFetcher.pull_multiple` completes
- **THEN** exactly 10 `Result` objects are returned in the array

#### Scenario: Errors captured in results
- **GIVEN** some URLs will fail
- **WHEN** `ConcurrentFetcher.pull_multiple` completes
- **THEN** failed fetches return `Result` with error populated (not raised exceptions)

#### Scenario: Default concurrency limit
- **WHEN** `ConcurrentFetcher.pull_multiple` is called without `max_concurrent`
- **THEN** default limit of 16 concurrent requests is used

## REMOVED Requirements

### Requirement: Adaptive concurrency based on system resources
**Reason**: System resource monitoring (`/proc` file reading) is inappropriate for a library. Applications should implement resource-aware concurrency at the infrastructure level if needed.

**Migration**: If you relied on adaptive concurrency:
1. Monitor system resources in your application
2. Adjust `max_concurrent` parameter based on your metrics
3. Example: `max_concurrent = system_memory_available? ? 16 : 4`

### Requirement: Async API methods returning Channel(Result)
**Reason**: Crystal's native fiber support makes async wrappers redundant. The async methods doubled API surface and created resource leak potential.

**Migration**: Replace async methods with fiber wrapping:
```crystal
# Before (v0.6.x)
channel = Fetcher.pull_async(url)
result = channel.receive

# After (v0.7.0+)
channel = Channel(Fetcher::Result).new
spawn { channel << Fetcher.pull(url) }
result = channel.receive

# For multiple URLs with timeout:
results = Array(Fetcher::Result).new
channels = urls.map do |url|
  ch = Channel(Fetcher::Result).new
  spawn { ch << Fetcher.pull(url) }
  ch
end
channels.each { |ch| results << ch.receive }
```

**Removed methods**:
- `Fetcher.pull_async(url, ...)`
- `Fetcher.pull_async(url, headers, etag, last_modified, ...)`
- `Fetcher.pull_rss_async(url, ...)`
- `Fetcher.pull_reddit_async(url, ...)`
- `Fetcher.pull_software_async(url, ...)`
- `Fetcher.pull_json_feed_async(url, ...)`
