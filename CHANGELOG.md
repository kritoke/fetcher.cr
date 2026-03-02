# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Error categorization with ErrorType enum
- Redirect control configuration
- SSL verification options

## [0.3.0] - 2026-03-01

### What's New

#### Rich Content Extraction
Get more from your feeds with automatic extraction of:
- **Full article content** - No more just summaries; get complete posts from RSS and Atom feeds
- **Author information** - Names and profile links automatically extracted
- **Categories and tags** - Organize content with feed-provided metadata
- **Media attachments** - Podcasts, downloads, and images captured in structured format
- **Feed-level details** - Title, description, language, and authors from the feed itself

#### JSON Feed Support
Now supports JSON Feed format (v1.0 and v1.1) in addition to RSS and Atom:
- Automatic detection for `.json` and `/feed.json` URLs
- Full feature parity with RSS/Atom feeds
- No code changes needed - just works

#### Better Reliability
- **Automatic fallbacks** - Reddit feeds gracefully fall back to RSS when the JSON API is unavailable
- **Configurable timeouts** - Handle slow feeds with custom connection and read timeouts
- **HTTP compression** - Faster loading with automatic gzip/deflate support

#### Enhanced Test Coverage
Comprehensive test suite added to ensure reliability across all feed types and features.

### Compatibility
✅ **Fully backward compatible** - All existing code continues to work unchanged
✅ **No breaking changes** - All new fields have sensible defaults
✅ **Opt-in features** - New capabilities are available when you need them

### Technical Reference
For detailed API documentation, field names, and code examples, see [API.md](API.md).

---

## [0.2.1] - Previous Release

### Changed
- Bumped version number
- Removed compiled binary from tracking

### Fixed
- Various bug fixes from code review

---

## [0.2.0] - Major Refactor

### Changed
- Complete rewrite for v0.2.0
- Functional architecture
- Removed connection pooling for simplicity

[Unreleased]: https://github.com/kritoke/fetcher.cr/compare/v0.3.0..HEAD
[0.3.0]: https://github.com/kritoke/fetcher.cr/compare/v0.2.1..v0.3.0
[0.2.1]: https://github.com/kritoke/fetcher.cr/compare/v0.2.0..v0.2.1
[0.2.0]: https://github.com/kritoke/fetcher.cr/compare/v0.1.1..v0.2.0
