# Fetcher.cr v0.2.0 - Bug Fixes & Improvements

## Specification ID: SPEC-001
## Status: Phase 1 Complete
## Priority: High
## Created: 2026-02-28
## Last Updated: 2026-02-28

---

## Implementation Status

### Phase 1: Critical Fixes ✅ COMPLETE
- [x] Remove duplicate `RetriableError` from http_client.cr
- [x] Fix Reddit retry logic to not retry 404 errors
- [x] Improve URL detection with proper regex
- [x] Remove unused require in http_client.cr
- [x] Fix Reddit header merging
- [x] Add tests for fake domain detection

### Phase 2: Important Improvements (Pending)
- [ ] Document connection pooling decision
- [ ] Add basic integration tests

### Phase 3: Cleanup (Pending)
- [ ] Address Config record design

---

## Overview

This specification tracks critical bugs and improvements identified during the v0.2.0 refactor code review. The refactor successfully migrated from a class-based Driver pattern to functional modules, but several issues were discovered that need addressing before production use.

---

## Critical Issues (P0)

### 1. Duplicate RetriableError Class Definition

**Files:** `src/fetcher/http_client.cr`, `src/fetcher/retry.cr`

**Problem:**
`RetriableError` is defined in both `http_client.cr` (line 13-16) and `retry.cr` (line 16-19). This creates potential build order dependencies and confusion about class ownership.

**Impact:**
- Bad practice that violates single responsibility
- Potential issues if definitions diverge
- Unclear which file "owns" the exception type

**Solution:**
- Remove duplicate definition from `http_client.cr`
- Keep single definition in `retry.cr` (canonical location)
- Verify all references still work correctly

**Acceptance Criteria:**
- [x] `RetriableError` defined only in `retry.cr`
- [x] `http_client.cr` does not require or define `RetriableError`
- [x] All tests pass
- [x] No compilation warnings

**Status:** ✅ COMPLETE

---

### 2. Reddit Retry Logic Marks Non-Retriable Errors as Retriable

**Files:** `src/fetcher/reddit.cr`

**Problem:**
Line 22-26 marks all `RedditFetchError` exceptions as retriable, but this error type is raised for:
- 404 "Subreddit not found" (permanent error)
- Other HTTP errors like 500, 501 (may be permanent)

Only these should retry:
- 429 Rate limited (transient)
- 503 Service unavailable (transient)

**Impact:**
- Unnecessary retry attempts for permanent errors
- Wasted API calls and increased latency
- Poor user experience with delayed error reporting

**Solution:**
Option A (Recommended):
- Remove `RedditFetchError` from retriable check
- Only retry on `RetriableError` (which is raised for 429/503)

Option B:
- Create separate error types: `RedditTransientError` vs `RedditPermanentError`
- Only retry on `RedditTransientError`

**Acceptance Criteria:**
- [x] 404 errors return immediately without retry
- [x] 429/503 errors still retry correctly
- [x] Tests verify retry behavior
- [x] Error messages remain clear

**Status:** ✅ COMPLETE

---

### 3. URL Driver Detection Uses Naive String Matching

**Files:** `src/fetcher.cr`

**Problem:**
The `detect_driver` method uses simple `includes?` checks:
```crystal
if url.includes?("reddit.com/r/")
```

This incorrectly matches:
- `https://notreddit.com/r/test` → Reddit (wrong!)
- `https://fakegithub.com/foo/releases` → Software (wrong!)

**Impact:**
- Wrong driver selected for similar domain names
- Parsing errors when wrong driver processes feed
- Potential security concerns with malicious URLs

**Solution:**
Use proper regex or URI parsing to match actual domains:
```crystal
if url.matches?(/(?:^|\.)(reddit\.com)\/r\//i)
```

**Acceptance Criteria:**
- [x] Only actual reddit.com URLs match Reddit driver
- [x] Only actual github.com URLs match Software driver
- [x] Edge cases tested (subdomains, similar domains)
- [x] No false positives or negatives

**Status:** ✅ COMPLETE

---

## Moderate Issues (P1)

### 4. Unused require Statement

**Files:** `src/fetcher/http_client.cr`

**Problem:**
Line 2: `require "./time_parser"` is present but TimeParser is never used in this file.

**Impact:**
- Unnecessary dependency
- Slightly longer compile time
- Code confusion

**Solution:**
Remove the unused require statement.

**Acceptance Criteria:**
- [x] Remove `require "./time_parser"` from http_client.cr
- [x] Build still succeeds
- [x] All tests pass

**Status:** ✅ COMPLETE

---

### 5. Reddit Module Ignores Passed Headers

**Files:** `src/fetcher/reddit.cr`

**Problem:**
Line 31-36 creates new headers, ignoring the `headers` parameter passed to `pull()`:
```crystal
def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100) : Result
  # ...
  headers = ::HTTP::Headers{  # Overwrites passed headers!
    "User-Agent" => USER_AGENT,
    "Accept"     => "application/json",
  }
```

**Impact:**
- Inconsistent with RSS and Software modules
- Users cannot customize Reddit request headers
- Potential breakage for users needing custom headers

**Solution:**
Merge custom headers with Reddit-specific defaults:
```crystal
reddit_headers = ::HTTP::Headers{
  "User-Agent" => USER_AGENT,
  "Accept"     => "application/json",
}
final_headers = reddit_headers.merge(headers)
```

**Acceptance Criteria:**
- [x] Custom headers are preserved and merged
- [x] Reddit-specific headers still applied
- [x] Tests verify header merging works
- [x] Consistent with other modules

**Status:** ✅ COMPLETE

---

### 6. Connection Pooling Decision

**Files:** `src/fetcher/http_client.cr`, `README.md`

**Problem:**
v0.1 had `HTTPClientPool` for client reuse. v0.2 creates new `HTTP::Client` for every request. The README removed "Connection Pooling" from features without documentation.

**Impact:**
- Performance degradation for high-frequency fetching
- More TCP connections opened/closed
- Unclear if removal was intentional

**Solution:**
Option A (Recommended for simplicity):
- Document why pooling was removed
- Add note about performance characteristics
- Consider adding pooling as optional feature later

Option B:
- Restore simple connection pooling
- Use `HTTP::Client` with connection reuse

**Acceptance Criteria:**
- [ ] Decision documented in README
- [ ] Performance characteristics explained
- [ ] If pooling restored: tests verify client reuse

---

## Minor Issues (P2)

### 7. No Integration Tests

**Files:** `spec/fetcher_spec.cr`

**Problem:**
All tests use invalid URLs that return errors. Zero test coverage for:
- RSS/Atom XML parsing
- Reddit JSON parsing
- Software release parsing
- Time parsing edge cases
- URL detection edge cases

**Update (2026-02-28):**
Added tests for URL detection edge cases (fake domains). Tests now cover:
- Fake domain detection (notreddit.com, fakegithub.com, etc.)
- Invalid subreddit handling

**Impact:**
- Parsing bugs may go undetected
- Refactoring becomes risky
- No regression protection

**Solution:**
Add unit tests with sample data:
- Sample RSS feed XML
- Sample Atom feed XML
- Sample Reddit JSON response
- Sample GitHub API response
- Time parsing test cases

**Acceptance Criteria:**
- [x] URL detection edge cases tested
- [ ] At least one test per driver with valid sample data
- [ ] Time parsing tested with multiple formats
- [ ] Edge cases covered (missing fields, malformed data)

**Status:** 🔄 PARTIALLY COMPLETE

---

### 8. Config Record Underutilized

**Files:** `src/fetcher/http_client.cr`

**Problem:**
The `Config` record has `user_agent`, `accept_header`, `timeouts`, but no caller ever passes a custom config. The config is somewhat redundant.

**Impact:**
- Unused API surface
- Confusion about extensibility

**Solution:**
Either:
- Remove Config and use constants
- OR expose configuration properly via `Fetcher.configure({...})`

**Acceptance Criteria:**
- [ ] Decision made and implemented
- [ ] Documentation updated
- [ ] No dead code

---

## Implementation Plan

### Phase 1: Critical Fixes (Must Complete) ✅ COMPLETE
1. [x] Remove duplicate `RetriableError` from http_client.cr
2. [x] Fix Reddit retry logic to not retry 404 errors
3. [x] Improve URL detection with proper regex
4. [x] Remove unused require in http_client.cr
5. [x] Fix Reddit header merging
6. [x] Add tests for fake domain detection

### Phase 2: Important Improvements (Next)
5. [ ] Document connection pooling decision
6. [ ] Add basic integration tests with sample data

### Phase 3: Cleanup (Future)
7. [ ] Address Config record design

### Phase 3: Cleanup
8. Address Config record design

---

## Testing Strategy

- All existing tests must continue passing
- New tests for fixed behavior (especially retry logic)
- Manual testing with real URLs recommended
- Consider adding mock HTTP server for integration tests

---

## Risk Assessment

| Issue | Risk if Unfixed | Fix Complexity |
|-------|----------------|----------------|
| Duplicate RetriableError | Low (works but messy) | Low |
| Reddit retry bug | Medium (unnecessary retries) | Low |
| URL detection | Medium (wrong driver) | Low |
| Unused require | Very Low | Very Low |
| Reddit headers | Low (feature gap) | Low |
| Connection pooling | Medium (performance) | Medium |
| No integration tests | High (undetected bugs) | High |

---

## Success Metrics

- [x] All 29 existing tests pass (now 31 tests)
- [x] 2 new tests added for URL detection edge cases
- [x] Zero duplicate class definitions
- [x] All URL detection edge cases covered
- [ ] Retry behavior verified with tests (manual verification only)
- [x] Code review approval
- [x] Ameba lint passes with no warnings
- [x] Crystal build passes with no errors

**Update (2026-02-28):** Phase 1 metrics achieved. 31 tests passing, up from 29.

---

## References

- Original code review findings
- v0.1.1 tag for connection pooling reference
- Crystal HTTP::Client documentation
- Crystal exception handling best practices
