## Why

The codebase has several quality issues that affect maintainability and readability, including overly long function names (4+ words), excessively large files (>300-400 lines), duplicated code patterns violating DRY principles, and non-idiomatic Crystal usage. These issues make the code harder to understand, maintain, and extend.

## What Changes

- Rename internal functions with 4+ word names to be more concise (2-3 words max)
- Split large files (`software.cr`, `json_streaming_parser.cr`) into smaller, focused modules
- Extract and consolidate duplicated HTTP client setup logic into shared helpers
- Standardize error handling patterns across all driver modules
- Replace non-idiomatic Crystal patterns (excessive `.try` chaining, unnecessary `String.new()`, redundant type annotations) with idiomatic alternatives
- **NOT** renaming any public API functions (`Fetcher.pull()`, driver `pull()` methods, etc.)
- **Preserving** existing `Time.monotonic` usage in specs due to Crystal 1.18.2 constraints

## Capabilities

### New Capabilities
- `code-quality-improvements`: Refactoring and quality improvements that don't change external behavior or requirements

### Modified Capabilities
- None - this change focuses on implementation improvements without altering functional requirements

## Impact

- Internal function names will be shorter and more readable
- Code organization will be improved with better file separation
- Reduced code duplication through shared utilities
- More idiomatic Crystal code throughout the codebase
- No breaking changes to public APIs
- Improved maintainability and developer experience