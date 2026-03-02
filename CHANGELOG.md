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

### Added

#### Content & Author Extraction
- **Entry.content** - Now populated from RSS description/content:encoded and Atom content/summary
- **Entry.content_html** - HTML version of content (when different from plain text)
- **Entry.author** - Extracted from RSS dc:creator and Atom author/name
- **Entry.author_url** - Extracted from Atom author/uri
- **Entry.categories** - Array of tags/categories from RSS category and Atom category[@term]
- **Entry.attachments** - Array of enclosures/media files (podcasts, downloads)
- **Attachment** - New record type for enclosures with url, mime_type, size, duration
- **Author** - New record type for feed authors with name, url, avatar
- **Feed-level metadata** in Result:
  - `feed_title` - Feed/channel title
  - `feed_description` - Feed description/subtitle
  - `feed_language` - Feed language code
  - `feed_authors` - Array of feed-level authors

#### JSON Feed Support
- **JSONFeed** - Complete JSON Feed v1.1 parser module
- **Auto-detection** - Automatic JSON Feed detection for .json, /feed.json, /feeds/json URLs
- **Full feature parity** with RSS/Atom:
  - content_html and content_text support
  - Item and feed-level authors
  - Tags as categories
  - Attachments (podcasts, media)
  - Feed metadata (title, description, language, icon, favicon)
- **DriverType::JSONFeed** - New driver enum variant
- **pull_json_feed()** - Explicit JSON Feed fetching method

#### HTTP Improvements
- **RequestConfig** - Configuration record for HTTP requests
  - `connect_timeout` - Connection timeout (default: 10 seconds)
  - `read_timeout` - Read timeout (default: 30 seconds)
- **HTTP compression** - Accept-Encoding: gzip, deflate header support
- **Configurable timeouts** - All pull methods accept optional `config` parameter
- **Backward compatible** - All config parameters have sensible defaults

#### Reddit RSS Fallback
- **Automatic fallback** to RSS feed when JSON API fails
- **Improved reliability** - Handles rate limits and API errors gracefully
- **Same API** - No code changes needed for users

#### Test Coverage
- **16 tests** for content extraction features
- **16 tests** for JSON Feed parsing
- **11 tests** for HTTP improvements
- **9 integration tests** with test fixtures
- **3 test fixtures** for RSS, Atom, and JSON Feed

### Changed

#### Breaking Changes
- **NONE** - All changes are backward compatible
- All new fields have default values
- Existing API signatures unchanged (new params have defaults)

#### Improvements
- **Entry** record enhanced with new optional fields (content, author, categories, etc.)
- **Result** record enhanced with feed metadata fields
- **HTTPClient.fetch** now accepts RequestConfig parameter
- **All pull methods** accept RequestConfig parameter
- **HTMLUtils** module for centralized text sanitization
- **Factory methods** for Result (error/success) and Entry (create)

### Documentation
- Enhanced README with new feature examples

### Fixed
- Removed unused RequestConfig fields (max_redirects, follow_redirects, ssl_verify)
- Documented unimplemented features for future versions

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
