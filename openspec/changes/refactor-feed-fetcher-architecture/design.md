## Context

The current fetcher.cr implementation uses fragile regex-based URL detection to determine feed types, leading to misclassification and maintenance issues. The architectural review identified 10 core issues that need addressing, with content-type based detection being the foundation for a more robust approach.

Current state:
- Driver detection relies entirely on URL patterns
- No content-type header analysis
- Duplicate HTTP logic across drivers
- Weak error handling and validation

Constraints:
- Must maintain backward compatibility with existing API
- Crystal 1.18+ compatibility required
- Zero runtime dependencies beyond Crystal stdlib
- Performance must not regress significantly

## Goals / Non-Goals

**Goals:**
- Replace URL regex detection with content-type header analysis
- Maintain 100% backward compatibility with existing API
- Improve reliability and accuracy of feed type detection
- Enable proper error categorization and handling
- Create foundation for unified HTTP client architecture

**Non-Goals:**
- Complete rewrite of all drivers in this phase
- Breaking changes to public API
- Addition of new external dependencies
- Performance optimization beyond baseline

## Decisions

### 1. Content-Type Detection with Fallback Strategy
**Decision**: Implement content-type detection with graceful fallback to URL patterns
**Rationale**: Ensures maximum compatibility while improving detection accuracy. Servers that don't support HEAD requests or return generic content-types will still work via URL patterns.
**Alternative Considered**: Pure content-type detection only - rejected due to compatibility concerns.

### 2. HEAD Request Before GET
**Decision**: Send HEAD request to get content-type before full GET request
**Rationale**: Minimizes bandwidth usage and enables early driver selection. Most feed servers support HEAD requests.
**Alternative Considered**: GET with Range header - rejected due to complexity and lack of universal support.

### 3. Enhanced HTTP Client with HEAD Support
**Decision**: Add HEAD method to existing HTTPClient module
**Rationale**: Reuses existing connection handling, rate limiting, and error handling logic. Minimal code duplication.
**Alternative Considered**: Separate HTTP client for HEAD requests - rejected due to unnecessary complexity.

### 4. JSON Feed Content-Type Validation
**Decision**: Require both `application/json` content-type AND URL pattern validation
**Rationale**: Prevents misclassification of generic JSON APIs as JSON Feed format. Provides defense in depth.
**Alternative Considered**: JSON Feed detection by content-type alone - rejected due to high false positive rate.

### 5. Backward Compatible Method Signature
**Decision**: Add default parameters to `detect_driver` method
**Rationale**: Maintains existing API contract while enabling new functionality. Existing code continues to work unchanged.
**Alternative Considered**: New method name - rejected due to API fragmentation.

## Risks / Trade-offs

**[Risk]** Increased latency due to additional HEAD request
**Mitigation**: Implement connection reuse between HEAD and GET requests. Add configurable option to skip HEAD for known sources.

**[Risk]** Server doesn't support HEAD requests
**Mitigation**: Graceful fallback to URL-based detection with comprehensive error handling.

**[Risk]** Content-type headers are missing or incorrect
**Mitigation**: Robust parsing with fallback to URL patterns. Log warnings for debugging.

**[Risk]** Rate limiting complexity with HEAD requests
**Mitigation**: Apply same rate limiting rules to HEAD requests as GET requests. Use same domain-based rate limiters.

**[Risk]** Memory overhead from additional HTTP responses
**Mitigation**: HEAD responses contain only headers, minimal memory impact. Reuse existing response handling.

## Migration Plan

1. **Phase 1**: Implement content-type detection with fallback (completed)
2. **Phase 2**: Update all drivers to use unified HTTP client
3. **Phase 3**: Implement structured error handling
4. **Phase 4**: Add comprehensive integration tests
5. **Phase 5**: Performance optimization and documentation

Rollback strategy: Revert to previous version if critical issues are discovered. The backward compatible API ensures smooth rollback.

## Open Questions

1. **Should we cache content-type detection results?**
   - Pros: Reduce HEAD requests for repeated URLs
   - Cons: Cache invalidation complexity, memory usage
   - Decision needed: Implement simple TTL cache or skip for now?

2. **How to handle servers that redirect on HEAD but not GET?**
   - Current implementation follows redirects for both HEAD and GET
   - May need special handling for inconsistent redirect behavior

3. **Should we add support for custom content-type mappings?**
   - Allow users to register custom content-type to driver mappings
   - May be useful for custom feed formats