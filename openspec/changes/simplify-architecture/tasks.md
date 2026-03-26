## 1. Delete Dead Code

- [x] 1.1 Delete `src/fetcher/adaptive_concurrency_controller.cr`
- [x] 1.2 Delete `src/fetcher/simple_json_streaming_parser.cr`
- [x] 1.3 Delete `src/fetcher/working_json_streaming_parser.cr`
- [x] 1.4 Delete `src/fetcher/simple_xml_streaming_parser.cr`
- [x] 1.5 Delete `src/fetcher/connection_pool.cr`
- [x] 1.6 Delete `spec/adaptive_concurrency_controller_spec.cr`
- [x] 1.7 Remove deleted file requires from `src/fetcher.cr`

## 2. Remove Async API Methods

- [x] 2.1 Remove all `*_async` methods from `src/fetcher.cr` (8 methods total)
- [x] 2.2 Update requires in related files (reddit.cr, json_feed.cr)

## 3. Implement Circuit Breaker

- [x] 3.1 Create `src/fetcher/circuit_breaker.cr` with `CircuitBreaker` class
- [x] 3.2 Implement `State` enum (Closed, Open, HalfOpen)
- [x] 3.3 Implement `record_success` method
- [x] 3.4 Implement `record_failure` method
- [x] 3.5 Implement `allow_request?` method with state transitions
- [x] 3.6 Add per-domain circuit breaker registry (`CircuitBreaker::Registry`)
- [x] 3.7 Circuit breaker config already exists in `RequestConfig`:
  - `circuit_breaker_failure_threshold: Int32 = 5`
  - `circuit_breaker_recovery_timeout: Time::Span = 60.seconds`
  - `circuit_breaker_enabled: Bool = true`
- [x] 3.8 Integrate circuit breaker check into `CrestHttpClient.get` and `head`
- [x] 3.9 Record success/failure in circuit breaker after HTTP requests

## 4. Simplify ConcurrentFetcher

- [x] 4.1 Rewrite `ConcurrentFetcher.pull_multiple` with semaphore pattern
- [x] 4.2 Add `max_concurrent` parameter with default of 16
- [x] 4.3 Ensure all results are captured (success and error cases)

## 5. Update Tests

- [ ] 5.1 Create `spec/circuit_breaker_spec.cr` with unit tests
- [ ] 5.2 Test circuit breaker state transitions (Closed → Open → HalfOpen → Closed)
- [ ] 5.3 Test per-domain isolation
- [ ] 5.4 Test configuration options
- [ ] 5.5 Add tests for code paths not touched by compilation (Crystal lazy type evaluation)
  - JSON streaming parser Reddit path
  - JSON streaming parser JSON Feed path
  - Circuit breaker integration with CrestHttpClient
- [x] 5.6 Run full test suite and fix any failures (118 tests pass)

## 6. Documentation Updates

- [ ] 6.1 Update README to remove async API documentation
- [ ] 6.2 Add circuit breaker usage documentation to README
- [ ] 6.3 Add async pattern example for users (fiber + channel)
- [ ] 6.4 Update CHANGELOG with breaking changes and migration guide
- [ ] 6.5 Update API.md if it exists

## 7. Final Verification

- [x] 7.1 Run `crystal spec` - all tests pass
- [ ] 7.2 Run `ameba` linting - no errors
- [ ] 7.3 Verify compilation with `crystal build`
- [ ] 7.4 Update version in `shard.yml` to 0.7.0
