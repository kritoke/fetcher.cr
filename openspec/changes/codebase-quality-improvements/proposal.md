# Proposal: Codebase Quality Improvements

## Why

A comprehensive code review identified several areas requiring improvement across security, performance, readability, and maintainability. These issues affect the library's reliability, efficiency, and long-term maintainability.

### Key Issues Identified

1. **Security Concerns**
   - Incorrect exception type used for response size errors (labeled as DNS error)
   - Debug output using `puts` may leak sensitive URL information
   - No upper bounds validation on `limit` parameter

2. **Performance Bottlenecks**
   - Streaming parser claims to be lazy but loads all entries into memory
   - String concatenation in tight loops instead of StringBuilder
   - Regex patterns compiled on every call instead of being cached
   - Polling-based rate limiter wastes CPU cycles

3. **Readability Issues**
   - Complex nested conditionals in feed type detection
   - Magic numbers scattered throughout codebase
   - Inconsistent error handling patterns across modules

4. **Maintainability Concerns**
   - ~80% duplicate code between GitLab and Codeberg providers
   - Global mutable state makes testing difficult
   - Empty rescue blocks silently swallow errors
   - Configuration defaults scattered across multiple files

## Capabilities

### New Capabilities

- `response-size-validation`: Proper exception handling for response size limits with dedicated exception type
- `logging-infrastructure`: Replace debug `puts` statements with proper logging framework
- `limit-validation`: Add upper bounds validation for limit parameter across all fetch methods
- `streaming-parser-optimization`: True lazy streaming implementation for XML and JSON parsers
- `string-builder-optimization`: Use String::Builder for string concatenation in hot paths
- `regex-caching`: Pre-compile and cache regex patterns used in hot paths
- `error-handling-consistency`: Standardized error handling pattern across all modules
- `provider-code-deduplication`: Extract shared logic from GitLab/Codeberg providers
- `configuration-centralization`: Centralize all configuration defaults
- `error-logging`: Replace empty rescue blocks with proper error logging

### Modified Capabilities

- `http-client`: Add proper exception types and logging
- `circuit-breaker`: Add cleanup methods for global state
- `rate-limiter`: Improve with condition variable signaling

## Impact

### Affected Files
- `src/fetcher/crest_http_client.cr` - Exception types, logging
- `src/fetcher/circuit_breaker.cr` - Cleanup methods
- `src/fetcher/token_bucket_rate_limiter.cr` - Condition variables
- `src/fetcher/xml_streaming_parser.cr` - True streaming
- `src/fetcher/json_streaming_parser.cr` - True streaming
- `src/fetcher/streaming_rss_parser.cr` - String builder optimization
- `src/fetcher/fetcher.cr` - Regex caching, limit validation
- `src/fetcher/software.cr` - Code deduplication, regex caching
- `src/fetcher/rss.cr` - Error handling consistency
- `src/fetcher/json_feed.cr` - Error handling consistency
- `src/fetcher/reddit.cr` - Error handling consistency, logging
- `src/fetcher/request_config.cr` - Centralized defaults
- `src/fetcher/retry.cr` - Centralized defaults

### API Changes
- New exception type: `ResponseTooLargeError`
- New module: `Fetcher::Config` with centralized constants
- New method: `CrestHttpClient.clear_rate_limiters`
- New method: `CircuitBreaker::Registry.clear`
- No breaking changes to public API

### Dependencies
- No new external dependencies required
- Uses Crystal's built-in `Log` module for logging
