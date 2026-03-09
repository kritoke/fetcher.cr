## 1. Content-Type Detection Implementation

- [x] 1.1 Add HEAD method to HTTPClient module
- [x] 1.2 Update detect_driver method signature with headers and config parameters
- [x] 1.3 Implement content-type header analysis logic
- [x] 1.4 Add fallback to URL-based detection when HEAD fails
- [x] 1.5 Update all pull methods to pass headers and config to detect_driver
- [x] 1.6 Verify backward compatibility with existing tests
- [x] 1.7 Test compilation and run all existing tests

## 2. Unified HTTP Client Implementation

- [ ] 2.1 Create unified HTTP client interface
- [ ] 2.2 Migrate all drivers to use unified HTTP client
- [ ] 2.3 Implement proper connection pooling and resource management
- [ ] 2.4 Add comprehensive error handling for HTTP operations
- [ ] 2.5 Update tests to verify unified HTTP client behavior

## 3. Structured Error Handling Implementation

- [ ] 3.1 Define typed exception hierarchy
- [ ] 3.2 Implement HTTPError, ParsingError, ValidationError, TransientError classes
- [ ] 3.3 Update all drivers to throw typed exceptions
- [ ] 3.4 Update Result type to include error type information
- [ ] 3.5 Add error categorization tests

## 4. Standard URL Validation Implementation

- [ ] 4.1 Replace custom IP validation with Socket::IPAddress
- [ ] 4.2 Implement proper SSRF protection using system libraries
- [ ] 4.3 Add comprehensive URL validation tests
- [ ] 4.4 Update Entry creation to use standard validation

## 5. Separated Concerns Implementation

- [ ] 5.1 Create EntryParser interface
- [ ] 5.2 Implement driver-specific parser classes
- [ ] 5.3 Create EntryFactory for validated entry creation
- [ ] 5.4 Implement ResultBuilder for structured result construction
- [ ] 5.5 Refactor all drivers to use new architecture

## 6. Comprehensive Testing Implementation

- [ ] 6.1 Create real feed fixtures for all supported formats
- [ ] 6.2 Implement integration tests with actual endpoints
- [ ] 6.3 Add property-based testing for edge cases
- [ ] 6.4 Achieve 95%+ coverage on parsing logic
- [ ] 6.5 Add performance benchmarks

## 7. Token Bucket Rate Limiting Implementation

- [ ] 7.1 Implement token bucket algorithm
- [ ] 7.2 Replace global mutex hash with scalable rate limiting
- [ ] 7.3 Add support for per-domain and global rate limits
- [ ] 7.4 Implement configurable burst capacity and refill rates
- [ ] 7.5 Add concurrency tests for rate limiting

## 8. RFC Time Parsing Implementation

- [ ] 8.1 Replace custom format lists with Time.parse_rfc3339
- [ ] 8.2 Implement proper timezone handling
- [ ] 8.3 Add fallback to lenient parsing when necessary
- [ ] 8.4 Add comprehensive time parsing tests

## 9. Streaming Processing Implementation

- [ ] 9.1 Implement streaming XML/JSON parsing
- [ ] 9.2 Add hard memory limits with compression awareness
- [ ] 9.3 Implement early termination on size violations
- [ ] 9.4 Add memory safety tests

## 10. Consistent Configuration Implementation

- [ ] 10.1 Create unified FetcherConfig class
- [ ] 10.2 Pass config through entire call chain
- [ ] 10.3 Implement immutable configuration objects
- [ ] 10.4 Add default configuration with explicit overrides
- [ ] 10.5 Update all tests to verify configuration consistency

## 11. Documentation and Finalization

- [ ] 11.1 Update README with new features and usage examples
- [ ] 11.2 Add migration guide for breaking changes
- [ ] 11.3 Run final Ameba linting and fix issues
- [ ] 11.4 Verify all tests pass and performance benchmarks
- [ ] 11.5 Prepare release notes for v0.3.0