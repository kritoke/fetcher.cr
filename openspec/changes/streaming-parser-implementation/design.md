# Streaming Parser Implementation Design

## Context

### Current State
The fetcher library currently uses DOM-based parsing for all feed formats (RSS, Atom, JSON Feed, Reddit). This approach loads the entire document into memory before processing, which works well for small-to-medium feeds but becomes problematic for:
- Large feeds (> 10MB) that consume excessive memory
- High-concurrency scenarios where multiple feeds are processed simultaneously
- Resource-constrained environments (serverless functions, mobile devices)
- Feeds larger than available RAM

The existing `StreamingRSSParser` implementation attempts streaming but has critical flaws:
- Still accumulates all entries in an Array before returning (defeating streaming purpose)
- Lacks feed-level metadata extraction
- Uses complex manual parsing instead of leveraging existing DOM parser logic
- Has no comprehensive test coverage

### Constraints
- Must maintain backward compatibility with existing API
- Should not introduce new external dependencies
- Must handle malformed feeds robustly 
- Should provide automatic fallback to DOM parsing on errors
- Performance should be comparable or better than DOM parsing for small feeds

### Stakeholders
- **Library users**: Benefit from reduced memory usage and better scalability
- **High-volume applications**: Can process more feeds concurrently with less memory
- **Resource-constrained deployments**: Can handle large feeds that previously caused OOM errors
- **Maintainers**: Need clean, testable, and maintainable code

## Goals / Non-Goals

**Goals:**
1. Implement true streaming parsers using Crystal's pull parser architecture
2. Reduce memory footprint from O(n) to O(1) for feed processing
3. Maintain full feature parity with existing DOM parser
4. Provide automatic fallback to DOM parsing on streaming errors
5. Support both RSS/Atom and JSON/Reddit feed formats
6. Add comprehensive test coverage and performance benchmarks

**Non-Goals:**
1. Breaking changes to existing public API
2. Introducing new external dependencies
3. Replacing DOM parser as default (streaming remains opt-in)
4. Supporting every possible XML/JSON edge case beyond existing functionality
5. Implementing advanced streaming features like partial parsing or async processing

## Decisions

### 1. Pull Parser Architecture with Lazy Iterators

**Decision**: Use Crystal's built-in `XML::Reader` and `JSON::PullParser` with lazy iterator pattern.

**Rationale**:
- Leverages battle-tested standard library components
- Provides true streaming with minimal memory overhead
- `XML::Reader` is wrapper around libxml2's xmlReader (industry standard)
- `JSON::PullParser` is same engine used by `JSON.from_json`
- Lazy iterators provide Crystal-native interface (`Iterator(Entry)`)

**Alternative Considered**: Full state machine parser
- Would provide maximum control but much higher complexity
- Harder to maintain and test comprehensively
- Risk of missing edge cases in feed parsing

### 2. Hybrid Strategy for Item Parsing

**Decision**: Use streaming to find item boundaries, then DOM-parse individual items.

**Rationale**:
- Combines memory efficiency of streaming with simplicity of DOM parsing
- Reuses existing, well-tested item parsing logic
- Avoids complex manual parsing of nested XML/JSON structures
- Maintains consistency between streaming and DOM parser results

**Implementation Approach**:
```crystal
# For XML/RSS
while reader.read
  if reader.name == "item"
    item_xml = reader.read_outer_xml  # Extract just this item
    entry = RSSParser.parse_item(XML.parse(item_xml))  # Reuse existing logic
  end
end

# For JSON/Reddit  
pull.read_array do
  # Extract current post as JSON object string
  post_json = extract_current_object(pull)
  entry = parse_post_with_existing_logic(post_json)
end
```

### 3. MIME-Type Based Dispatcher

**Decision**: Automatically detect feed type and route to appropriate streaming parser.

**Rationale**:
- Maintains seamless auto-detection behavior of existing library
- Handles both content-type headers and URL patterns
- Provides consistent user experience regardless of feed format

**Implementation**:
- Check Content-Type header first (more reliable)
- Fallback to URL pattern matching (file extensions, known domains)
- Route to XML streaming for RSS/Atom, JSON streaming for Reddit/JSON feeds

### 4. Configuration-Driven Opt-In

**Decision**: Keep streaming parser opt-in via RequestConfig with sensible defaults.

**Rationale**:
- Ensures backward compatibility
- Allows users to choose based on their specific needs
- DOM parser remains default for robustness with malformed feeds
- Advanced users can opt-in for memory-sensitive scenarios

**Configuration Options**:
```crystal
record RequestConfig,
  use_streaming_parser : Bool = false,      # Opt-in flag
  max_streaming_memory : Int32 = 10_485_760 # 10MB buffer limit
```

### 5. Automatic Fallback with Graceful Degradation

**Decision**: Automatically fallback to DOM parser on any streaming error.

**Rationale**:
- Maintains robustness for malformed or edge-case feeds
- Streaming parser may be more sensitive to certain malformed structures
- Users get best of both worlds: memory efficiency when possible, reliability always
- Seamless experience - users don't need to handle streaming-specific errors

**Fallback Logic**:
- Catch any exception during streaming parsing
- Log warning about fallback (for debugging)
- Process same feed with DOM parser
- Return identical Result structure

## Risks / Trade-offs

### Risk 1: Streaming Parser Fragility
**Risk**: Streaming parsers may be more sensitive to malformed XML/JSON than DOM parsers
**Mitigation**: 
- Implement comprehensive fallback to DOM parser
- Add extensive test coverage with malformed feed fixtures
- Log warnings on fallback to help identify problematic feeds

### Risk 2: Performance Overhead for Small Feeds
**Risk**: Streaming parser may have slightly higher overhead for small feeds due to streaming setup
**Mitigation**: 
- Benchmark performance across feed sizes
- Document recommendation to use DOM parser for small feeds (< 1MB)
- Keep streaming opt-in so users can choose based on their feed characteristics

### Risk 3: Memory Limit Configuration Complexity
**Risk**: Users may struggle with configuring appropriate memory limits
**Mitigation**: 
- Provide sensible defaults (10MB)
- Clear documentation with examples
- Auto-tuning based on available system memory (future enhancement)

### Risk 4: Incomplete Feature Parity
**Risk**: Streaming parser may miss some edge cases handled by DOM parser
**Mitigation**: 
- Comprehensive test suite covering all existing DOM parser test cases
- Use hybrid strategy to reuse existing item parsing logic
- Regular verification that both parsers produce identical results

### Risk 5: Iterator Interface Complexity
**Risk**: Iterator-based interface may be less familiar to some users
**Mitigation**: 
- Provide both iterator and array interfaces
- Maintain existing pull methods that return Result (with entries as Array)
- Clear documentation with usage examples for both approaches

## Migration Plan

### Phase 1: Core Infrastructure (Low Risk)
1. Implement lazy iterator infrastructure
2. Create XML streaming parser with hybrid strategy
3. Add basic configuration options
4. Implement automatic fallback mechanism

### Phase 2: JSON/Reddit Support (Medium Risk)
1. Implement JSON streaming parser with hybrid strategy
2. Add MIME-type dispatcher
3. Extend configuration options
4. Add comprehensive test coverage

### Phase 3: Performance Optimization (Medium Risk)
1. Add performance benchmarks
2. Implement memory limit enforcement
3. Add system memory auto-tuning capability
4. Optimize hybrid parsing performance

### Phase 4: Documentation and Release (Low Risk)
1. Update README.md with streaming parser documentation
2. Add API.md documentation
3. Create usage examples and best practices
4. Release as minor version (v0.7.0)

### Rollback Strategy
- Streaming parser is opt-in, so disabling it reverts to previous behavior
- If critical issues found, can disable streaming parser entirely via configuration
- Major issues can be addressed by reverting the feature branch

## Open Questions

1. **Memory Limit Enforcement**: Should we enforce hard memory limits or rely on OS limits?
   - Recommendation: Start with soft limits (logging warnings) and add hard limits in v0.8.0

2. **Iterator vs Array Interface**: Should we provide both or focus on one?
   - Recommendation: Provide both - keep existing array interface for compatibility, add iterator for advanced use cases

3. **Default Behavior for Large Feeds**: Should we automatically enable streaming for feeds > X MB?
   - Recommendation: No - keep explicit opt-in to avoid unexpected behavior changes

4. **Performance Benchmark Thresholds**: What constitutes acceptable performance?
   - Recommendation: Streaming should be within 20% of DOM parser for small feeds, significantly better for large feeds

5. **Error Reporting Granularity**: How detailed should fallback logging be?
   - Recommendation: Log feed URL and error type, but avoid sensitive data in logs