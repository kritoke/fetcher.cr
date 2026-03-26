# Streaming Parser Implementation

## Why

The current fetcher library loads entire feed documents into memory before parsing, which creates significant memory overhead for large feeds (> 10MB) and limits scalability in high-concurrency scenarios. Implementing proper streaming parsers using Crystal's pull parser architecture will provide memory-efficient feed processing while maintaining compatibility with existing functionality.

## What Changes

- **New Streaming Parser Architecture**
  - Implement lazy iterator-based streaming parsers for RSS/Atom and JSON feeds
  - Use XML::Reader for XML/RSS/Atom feeds (wrapper around libxml2's xmlReader)
  - Use JSON::PullParser for Reddit JSON feeds
  - Implement hybrid strategy: stream to find items, then DOM-parse individual items

- **Memory Efficiency Improvements**
  - Reduce memory footprint from O(n) to O(1) for feed processing
  - Support feeds larger than available RAM through streaming processing
  - Add configurable memory limits for streaming operations

- **API Enhancements**
  - Add `use_streaming_parser` option to RequestConfig (default: false)
  - Add `max_streaming_memory` configuration for buffer limits
  - Provide both streaming and DOM parser options with automatic fallback

- **Performance Optimizations**
  - Enable real-time entry processing without waiting for full document load
  - Reduce garbage collection pressure in high-concurrency scenarios
  - Support taking limited entries from large feeds efficiently

- **Error Handling and Robustness**
  - Implement automatic fallback to DOM parsing on streaming errors
  - Add comprehensive test coverage for streaming parser edge cases
  - Maintain full feature parity with existing DOM parser

## Capabilities

### New Capabilities

- `streaming-parser-architecture`: Core streaming parser implementation using pull parser architecture with lazy iterators
- `xml-rss-streaming`: Memory-efficient RSS/Atom parsing using XML::Reader with hybrid strategy
- `json-reddit-streaming`: Efficient Reddit JSON parsing using JSON::PullParser with selective skipping
- `streaming-configuration`: Configuration options for streaming parser behavior and memory limits
- `streaming-error-handling`: Robust error handling with automatic fallback to DOM parsing

### Modified Capabilities

- `rss-parsing`: Add support for streaming parser option while maintaining existing DOM parser behavior
- `json-feed-parsing`: Add support for streaming parser option for JSON feeds
- `reddit-parsing`: Add support for streaming parser option for Reddit JSON feeds

## Impact

### Affected Code
- `src/fetcher/rss.cr` - Add streaming parser integration
- `src/fetcher/json_feed.cr` - Add streaming parser integration  
- `src/fetcher/reddit.cr` - Add streaming parser integration
- `src/fetcher/request_config.cr` - Add streaming configuration options
- `src/fetcher/streaming_rss_parser.cr` - Replace with proper lazy iterator implementation
- Create new `src/fetcher/streaming_json_parser.cr`

### API Changes
- **Non-breaking**: New optional configuration parameters in RequestConfig
- **Backward compatible**: Existing API remains unchanged, streaming is opt-in
- **New capabilities**: Iterator-based entry processing for advanced use cases

### Dependencies
- No new dependencies required
- Leverage existing Crystal standard library components (XML::Reader, JSON::PullParser)

### Testing
- Add comprehensive test suite for streaming parser functionality
- Include large feed fixtures (> 10MB) for memory testing
- Add performance benchmarks to verify memory savings
- Test automatic fallback behavior on malformed feeds
