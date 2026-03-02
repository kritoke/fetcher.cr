# API Reference

Technical API documentation for Fetcher v0.3.0.

## Table of Contents

- [Data Structures](#data-structures)
- [Public Methods](#public-methods)
- [Configuration](#configuration)
- [Feed Format Support](#feed-format-support)

---

## Data Structures

### Result

```crystal
record Result,
  # Core fields
  entries : Array(Entry),
  etag : String?,
  last_modified : String?,
  site_link : String?,
  favicon : String?,
  error_message : String?,
  
  # Feed metadata (v0.3.0+)
  feed_title : String?,
  feed_description : String?,
  feed_language : String?,
  feed_authors : Array(Author)
```

### Entry

```crystal
record Entry,
  title : String,
  url : String,
  source_type : String,  # "rss", "atom", "jsonfeed", "reddit", "github", etc.
  
  # Rich content (v0.3.0+)
  content : String,           # Full content
  content_html : String?,     # HTML version
  author : String?,           # Author name
  author_url : String?,       # Author URL
  categories : Array(String), # Tags/categories
  attachments : Array(Attachment), # Media files
  
  # Existing fields
  published_at : Time?,
  version : String?           # For software releases
```

### Author

```crystal
record Author,
  name : String?,
  url : String?,
  avatar : String?
```

### Attachment

```crystal
record Attachment,
  url : String,
  mime_type : String,
  title : String?,
  size_in_bytes : Int64?,
  duration_in_seconds : Int32?
```

### RequestConfig (v0.3.0+)

```crystal
record RequestConfig,
  connect_timeout : Time::Span = 10.seconds,
  read_timeout : Time::Span = 30.seconds
```

---

## Public Methods

### Main Pull Methods

```crystal
# Auto-detects feed type and fetches
Fetcher.pull(
  url : String,
  headers : HTTP::Headers? = nil,
  etag : String? = nil,
  last_modified : String? = nil,
  limit : Int32? = nil,
  config : RequestConfig? = nil
) : Result

# Force RSS/Atom driver
Fetcher.pull_rss(
  url : String,
  headers : HTTP::Headers? = nil,
  etag : String? = nil,
  last_modified : String? = nil,
  limit : Int32? = nil,
  config : RequestConfig? = nil
) : Result

# Force Reddit driver
Fetcher.pull_reddit(
  url : String,
  headers : HTTP::Headers? = nil,
  etag : String? = nil,
  last_modified : String? = nil,
  limit : Int32? = nil,
  config : RequestConfig? = nil
) : Result

# Force Software releases driver
Fetcher.pull_software(
  url : String,
  headers : HTTP::Headers? = nil,
  etag : String? = nil,
  last_modified : String? = nil,
  limit : Int32? = nil,
  config : RequestConfig? = nil
) : Result

# Force JSON Feed driver (v0.3.0+)
Fetcher.pull_json_feed(
  url : String,
  headers : HTTP::Headers? = nil,
  etag : String? = nil,
  last_modified : String? = nil,
  limit : Int32? = nil,
  config : RequestConfig? = nil
) : Result
```

### HTTP Client Methods

```crystal
# Low-level fetch with compression support
HTTPClient.fetch(
  url : String,
  headers : HTTP::Headers? = nil,
  config : RequestConfig? = nil
) : HTTP::Client::Response
```

---

## Configuration

### RequestConfig Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `connect_timeout` | `Time::Span` | `10.seconds` | Connection timeout |
| `read_timeout` | `Time::Span` | `30.seconds` | Read timeout |

### Usage Examples

```crystal
# Default configuration
result = Fetcher.pull("https://example.com/feed.xml")

# Custom timeouts
config = Fetcher::RequestConfig.new(
  connect_timeout: 30.seconds,
  read_timeout: 60.seconds
)
result = Fetcher.pull("https://slow.example.com/feed.xml", config: config)

# With caching headers
headers = HTTP::Headers{
  "Authorization" => "Bearer token"
}
result = Fetcher.pull(
  "https://example.com/feed.xml",
  headers: headers,
  etag: "abc123",
  last_modified: "Wed, 01 Jan 2025 00:00:00 GMT",
  limit: 50
)
```

---

## Feed Format Support

### RSS 2.0

**Extracted fields:**
- `title`, `link`, `description`, `pubDate`
- `content:encoded` → `Entry.content`
- `dc:creator` → `Entry.author`
- `enclosure` → `Entry.attachments`
- `category` → `Entry.categories`
- Channel metadata → `Result.feed_*` fields

**Also supports:**
- RSS 1.0/RDF (basic support)
- Content-encoded module
- Dublin Core namespace

### Atom 1.0

**Extracted fields:**
- `title`, `link`, `published`, `updated`
- `content` (HTML, text, xhtml types) → `Entry.content`
- `summary` → `Entry.content` (fallback)
- `author/name`, `author/uri` → `Entry.author`, `Entry.author_url`
- `category[@term]` → `Entry.categories`
- Feed metadata → `Result.feed_*` fields

### JSON Feed 1.0/1.1

**Extracted fields:**
- `title`, `url`, `id`
- `content_html`, `content_text` → `Entry.content_html`, `Entry.content`
- `authors` array → `Entry.author`, `Result.feed_authors`
- `tags` → `Entry.categories`
- `attachments` → `Entry.attachments`
- `date_published`, `date_modified` → `Entry.published_at`
- Feed metadata → `Result.feed_*` fields

**Auto-detection patterns:**
- URLs ending in `.json`
- URLs containing `/feed.json`
- URLs containing `/feeds/json`

### Reddit

**Auto-detection:**
- URLs matching `reddit.com/r/`

**Fallback:**
- Automatic fallback to RSS feed when JSON API fails
- Handles rate limits and API errors gracefully

### Software Releases

**Auto-detection:**
- `github.com/.../releases`
- `gitlab.com/.../-/releases`
- `codeberg.org/.../releases`

**Extracted fields:**
- Release title → `Entry.title`
- Release URL → `Entry.url`
- Version tag → `Entry.version`
- Release notes → `Entry.content`
- Assets → `Entry.attachments`

---

## Driver Detection Logic

The library automatically detects the feed type based on URL patterns:

| URL Pattern | Driver |
|-------------|--------|
| `reddit.com/r/` | Reddit |
| `github.com/.../releases` | Software |
| `gitlab.com/.../-/releases` | Software |
| `codeberg.org/.../releases` | Software |
| `.json`, `/feed.json`, `/feeds/json` | JSON Feed |
| All others | RSS |

---

## Error Handling

All methods return a `Result` struct. Check for errors:

```crystal
result = Fetcher.pull("https://example.com/feed.xml")

if error = result.error_message
  # Handle error
  puts "Error: #{error}"
else
  # Process entries
  result.entries.each { |entry| puts entry.title }
end
```

---

## Version History

- **v0.3.0** - Added content extraction, JSON Feed support, RequestConfig
- **v0.2.1** - Bug fixes and cleanup
- **v0.2.0** - Functional rewrite
- **v0.1.1** - Dependency fixes
- **v0.1.0** - Initial release
