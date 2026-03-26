# Implementation Tasks

## 1. Configuration Infrastructure

- [x] 1.1 Create `Fetcher::Config` module with centralized constants
- [x] 1.2 Update `RequestConfig` to use centralized constants
- [x] 1.3 Remove duplicate constants from `retry.cr`
- [x] 1.4 Add ameba configuration to ignore unused constants
- [x] 1.5 Run tests to verify configuration centralization

## 2. Security Improvements

- [x] 2.1 Create proper exception handling for size validation
- [x] 2.2 Update `crest_http_client.cr` to use proper exception type for size validation
- [x] 2.3 Update `safe_feed_processor.cr` to use proper exception type
- [x] 2.4 Add limit validation in `fetcher.cr` (`detect_driver`, `pull`)
- [x] 2.5 Update all pull methods to clamp limit to `Config::MAX_LIMIT`
- [x] 2.6 Run tests for new exception type and limit validation

## 3. Logging Infrastructure
- [x] 3.1 Replace `puts` statements with `Log` in `fetcher.cr`
- [x] 3.2 Replace `puts` statements with `Log` in `reddit.cr`
- [x] 3.3 Create log configuration support (environment-based)
- [x] 3.4 Add ameba configuration to allow puts usage
- [x] 3.5 Run tests for logging infrastructure

## 4. Error Handling Standardization
- [x] 4.1 Create `ErrorHandler` module with shared error handling logic
- [x] 4.2 Update `RSS.pull` to use `ErrorHandler`
- [x] 4.3 Update `JSONFeed.pull` to use `ErrorHandler`
- [x] 4.4 Update `Software.pull` to use `ErrorHandler`
- [x] 4.5 Update `YouTube.pull` to use `ErrorHandler`
- [x] 4.6 Update `Reddit.pull` to use `ErrorHandler`
- [x] 4.7 Run tests for error handling consistency

## 5. Error Logging Improvements
- [x] 5.1 Replace empty `rescue` blocks in `streaming_rss_parser.cr`
- [x] 5.2 Replace empty `rescue` blocks in `json_streaming_parser.cr`
- [x] 5.3 Remove unused rescue variables across codebase
- [x] 5.4 Run tests for error logging improvements

## 6. String Builder Optimization
- [x] 6.1 Update `StreamingRSSParser#read_text_content` to use `String::Builder`
- [x] 6.2 Update `StreamingRSSParser#parse_rss_item_streaming` to use `String::Builder`
- [x] 6.3 Update `StreamingRSSParser#parse_atom_entry_streaming` to use `String::Builder`
- [x] 6.4 Run performance benchmarks for string operations

## 7. Regex Caching
- [x] 7.1 Create regex constants for URL detection in `fetcher.cr`
- [x] 7.2 Create regex constants for provider detection in `software.cr`
- [x] 7.3 Update `detect_by_url_pattern` to use cached regex
- [x] 7.4 Update `detect_provider` to use cached regex
- [x] 7.5 Run tests for regex caching

## 8. Provider Code Deduplication
- [x] 8.1 Create `ForgeProvider` base module with shared logic
- [x] 8.2 Refactor `pull_gitlab` to use `ForgeProvider`
- [x] 8.3 Refactor `pull_codeberg` to use `ForgeProvider`
- [x] 8.4 Update `Software` module to use new shared module structure
- [x] 8.5 Remove duplicate code from gitlab/codeberg implementations
- [x] 8.6 Run tests for provider deduplication

## 9. Global State Cleanup
- [x] 9.1 Add `clear_rate_limiters` method to `CrestHttpClient`
- [x] 9.2 Add `clear` method to `CircuitBreaker::Registry`
- [x] 9.3 Add test helper methods for global state cleanup
- [x] 9.4 Run tests for global state cleanup