# API Reference

Technical API documentation for Fetcher v0.5.1.

## Table of Contents

- [Data Structures](#data-structures)
- [Public Methods](#public-methods)
- [Configuration](#configuration)
- [Feed Format Support](#feed-format-support)

---

## Data Structures

### ErrorKind (v0.4.0+)

Enum for categorized error types:

```crystal
enum ErrorKind
  DNSError        # DNS resolution failed
  Timeout         # Connection or read timeout
  InvalidURL      # URL validation failed
  InvalidFormat   # Feed format parsing failed
  HTTPError       # HTTP error response
  RateLimited     # Rate limited by API
  ServerError     # Server error (5xx)
  Unknown         # Unknown error
end
```

### Error (v0.4.0+)

Structured error record with context:

```crystal
record Error,
  kind : ErrorKind,      # Error category
  message : String,      # Human-readable message
  status_code : Int32?,  # HTTP status code if applicable
  url : String?,         # URL that caused the error
  driver : String?       # Driver that was used

# Factory methods
Error.dns(message)
Error.timeout(message)
Error.invalid_url(message)
Error.invalid_format(message)
Error.http(status_code, message, url)
Error.rate_limited(message)
Error.server_error(status_code, message)
Error.unknown(message)
end
```

### SourceType (v0.4.0+)

Type-safe enum for feed sources:

```crystal
enum SourceType
  RSS        # RSS 1.0/2.0
  Atom       # Atom
  JSONFeed   # JSON Feed
  Reddit     # Reddit
  GitHub     # GitHub releases
  GitLab     # GitLab releases
  Codeberg   # Codeberg releases

  # Convert to string
  def to_s : String  # "rss", "atom", etc.

  # Parse from string
  def self.from_string(value : String) : SourceType
end
```

### Result

```crystal
record Result,
  # Core fields
  entries : Array(Entry),
  etag : String?,
  last_modified : String?,
  site_link : String?,
  favicon : String?,
  error : Error?,             # Structured error (v0.4.0+)
  error_message : String?,    # Backward compatible accessor
  
  # Feed metadata (v0.3.0+)
  feed_title : String?,
  feed_description : String?,
  feed_language : String?,
  feed_authors : Array(Author)

# Methods
def success? : Bool  # Returns true if no error
def error_message : String?  # Backward compatible
```

### Entry

```crystal
record Entry,
  title : String,
  url : String,
  source_type : SourceType,  # Type-safe enum (v0.4.0+), was String
   
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

### RequestConfig (v0.4.0+)

```crystal
record RequestConfig,
  connect_timeout : Time::Span = 10.seconds,
  read_timeout : Time::Span = 30.seconds,
  max_requests_per_second : Int32? = nil  # Rate limiting (nil = disabled)
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
| `max_requests_per_second` | `Int32?` | `nil` | Rate limit per domain (nil = disabled) |
| `max_concurrent_requests` | `Int32?` | `nil` | Max concurrent requests (reserved) |
| `max_redirects` | `Int32` | `5` | Maximum redirect follows |
| `follow_redirects` | `Bool` | `true` | Follow HTTP redirects |
| `ssl_verify` | `Bool` | `true` | Verify SSL certificates |
| `rate_limit_capacity` | `Float64` | `10.0` | Token bucket burst capacity (v0.5.0+) |
| `rate_limit_refill_rate` | `Float64` | `1.0` | Token refill rate per second (v0.5.0+) |
| `max_retries` | `Int32` | `3` | Maximum retry attempts |
| `base_delay` | `Time::Span` | `1.second` | Base delay for exponential backoff |
| `max_delay` | `Time::Span` | `30.seconds` | Maximum delay cap |
| `exponential_base` | `Float64` | `2.0` | Exponential backoff multiplier |

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

# Rate limiting with token bucket (v0.5.0+)
config = Fetcher::RequestConfig.new(
  rate_limit_capacity: 10.0,      # Allow burst of 10 requests
  rate_limit_refill_rate: 2.0     # Refill 2 tokens per second
)
result = Fetcher.pull("https://api.example.com/feed.xml", config: config)

# Simple rate limiting (v0.4.0+)
config = Fetcher::RequestConfig.new(
  max_requests_per_second: 10
)
result = Fetcher.pull("https://api.example.com/feed.xml", config: config)

# Combined configuration with retry
config = Fetcher::RequestConfig.new(
  connect_timeout: 30.seconds,
  read_timeout: 60.seconds,
  max_retries: 5,
  base_delay: 2.seconds,
  rate_limit_capacity: 20.0,
  rate_limit_refill_rate: 5.0
)

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

### Backward Compatible (v0.1.0+)

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

### Type-Safe Error Handling (v0.4.0+)

```crystal
result = Fetcher.pull("https://example.com/feed.xml")

# Check success
if result.success?
  result.entries.each { |entry| puts entry.title }
else
  error = result.error
  puts "Error: #{error.message}"
  puts "Kind: #{error.kind}"  # ErrorKind enum
  
  # Pattern match on error type
  case error.kind
  when .timeout?
    puts "Request timed out"
  when .rate_limited?
    puts "Rate limited, retry after cooling period"
  when .http_error?
    puts "HTTP #{error.status_code}"
  when .dns_error?
    puts "DNS resolution failed"
  end
end
```

---

## Version History

- **v0.4.0** - Structured error handling, SourceType enum, rate limiting, enhanced security
- **v0.3.0** - Added content extraction, JSON Feed support, RequestConfig
- **v0.2.1** - Bug fixes and cleanup
- **v0.2.0** - Functional rewrite
- **v0.1.1** - Dependency fixes
- **v0.1.0** - Initial release
