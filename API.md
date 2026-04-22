# API Reference

Technical API documentation for Fetcher v0.9.4.

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
  TooLarge        # Response exceeded size limit
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
   
  # Discussion/comment fields (v0.8.0+)
  comment_url : String?,      # URL to discussion/comments
  commentary_url : String?,   # Related link (e.g., Daring Fireball style)
  is_discussion_url : Bool,   # True if main URL IS a discussion thread
   
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

### RequestConfig (v0.9.0+)

```crystal
Fetcher::RequestConfig.new(
  timeout : TimeoutConfig = TimeoutConfig.new,
  retry : RetryConfig = RetryConfig.new,
  circuit_breaker : CircuitBreakerConfig = CircuitBreakerConfig.new,
  rate_limit : RateLimitConfig = RateLimitConfig.new,
  streaming : StreamingConfig = StreamingConfig.new,
  cache_config : CacheConfig = CacheConfig.new,
  max_redirects : Int32 = 5,
  follow_redirects : Bool = true,
  ssl_verify : Bool = true,
  driver_detection_mode : DriverDetectionMode = Auto,
  error_detail_level : ErrorDetailLevel = Debug,
  max_concurrent_requests : Int32? = nil
)
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

---

## Configuration

### Sub-Configs

#### TimeoutConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `connect` | `Time::Span` | `10.seconds` | Connection timeout |
| `read` | `Time::Span` | `30.seconds` | Read timeout |

#### RetryConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `max_retries` | `Int32` | `3` | Maximum retry attempts |
| `base_delay` | `Time::Span` | `1.second` | Base delay for exponential backoff |
| `max_delay` | `Time::Span` | `30.seconds` | Maximum delay cap |
| `exponential_base` | `Float64` | `2.0` | Exponential backoff multiplier |

#### CircuitBreakerConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enabled` | `Bool` | `true` | Enable circuit breaker |
| `failure_threshold` | `Int32` | `5` | Failures before opening circuit |
| `recovery_timeout` | `Time::Span` | `60.seconds` | Wait before testing recovery |

#### RateLimitConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `requests_per_second` | `Int32?` | `nil` | Rate limit per domain (nil = disabled) |
| `capacity` | `Float64` | `10.0` | Token bucket burst capacity |
| `refill_rate` | `Float64` | `1.0` | Token refill rate per second |

#### StreamingConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enabled` | `Bool` | `false` | Enable streaming parser |
| `max_memory` | `Int32` | `10_485_760` | Max bytes before aborting (10MB) |
| `debug` | `Bool` | `false` | Debug logging for streaming |

#### CacheConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enabled` | `Bool` | `true` | Enable caching |
| `max_size` | `Int32` | `1000` | Max cached entries |
| `default_ttl` | `Time::Span` | `5.minutes` | Default TTL |

### RequestConfig Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `timeout` | `TimeoutConfig` | defaults | Connection and read timeouts |
| `retry` | `RetryConfig` | defaults | Retry behavior |
| `circuit_breaker` | `CircuitBreakerConfig` | defaults | Circuit breaker settings |
| `rate_limit` | `RateLimitConfig` | defaults | Rate limiting |
| `streaming` | `StreamingConfig` | defaults | Streaming parser options |
| `cache_config` | `CacheConfig` | defaults | Caching options |
| `max_redirects` | `Int32` | `5` | Maximum redirect follows |
| `follow_redirects` | `Bool` | `true` | Follow HTTP redirects |
| `ssl_verify` | `Bool` | `true` | Verify SSL certificates |
| `driver_detection_mode` | `DriverDetectionMode` | `Auto` | How to detect feed type |
| `error_detail_level` | `ErrorDetailLevel` | `Debug` | Verbosity of error logging |
| `max_concurrent_requests` | `Int32?` | `nil` | Request semaphore limit |
| `gitlab_token` | `String?` | `nil` | GitLab API token for authenticated requests (v0.9.3+) |
| `codeberg_token` | `String?` | `nil` | Codeberg API token for authenticated requests (v0.9.3+) |
| `ssl_verify_bypass_acknowledged` | `Bool` | `false` | Acknowledge SSL verification bypass for self-signed certs (v0.9.3+) |
| `reddit_client_id` | `String?` | `nil` | Reddit OAuth client ID (v0.9.4+) |
| `reddit_client_secret` | `String?` | `nil` | Reddit OAuth client secret (v0.9.4+) |
| `reddit_username` | `String?` | `nil` | Reddit account username for OAuth (v0.9.4+) |
| `reddit_password` | `String?` | `nil` | Reddit account password for OAuth (v0.9.4+) |

### Usage Examples

```crystal
# Default configuration
result = Fetcher.pull("https://example.com/feed.xml")

# Custom timeouts
config = Fetcher::RequestConfig.new(
  timeout: Fetcher::TimeoutConfig.new(connect: 30.seconds, read: 60.seconds)
)
result = Fetcher.pull("https://slow.example.com/feed.xml", config: config)

# Rate limiting
config = Fetcher::RequestConfig.new(
  rate_limit: Fetcher::RateLimitConfig.new(requests_per_second: 10)
)
result = Fetcher.pull("https://api.example.com/feed.xml", config: config)

# Token bucket rate limiting
config = Fetcher::RequestConfig.new(
  rate_limit: Fetcher::RateLimitConfig.new(capacity: 10.0, refill_rate: 2.0)
)
result = Fetcher.pull("https://api.example.com/feed.xml", config: config)

# Combined configuration
config = Fetcher::RequestConfig.new(
  timeout: Fetcher::TimeoutConfig.new(connect: 30.seconds, read: 60.seconds),
  retry: Fetcher::RetryConfig.new(max_retries: 5, base_delay: 2.seconds),
  rate_limit: Fetcher::RateLimitConfig.new(capacity: 20.0, refill_rate: 5.0),
  circuit_breaker: Fetcher::CircuitBreakerConfig.new(failure_threshold: 10)
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
- `<comments>` → `Entry.comment_url` (v0.8.3+)
- Channel metadata → `Result.feed_*` fields

**Comment URL extraction (v0.8.0+):**
- `<link rel="comments">` → `Entry.comment_url`
- `<link rel="replies">` → `Entry.comment_url`
- `<comments>url</comments>` → `Entry.comment_url` (fallback)
- URL pattern detection: `/comments/`, `/item?id=`, `/s/`, `/discuss`, `/r/`

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
- `<link rel="related">` → `Entry.commentary_url` (Daring Fireball pattern)
- `<link rel="comments">`, `<link rel="replies">` → `Entry.comment_url`
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

- **v0.9.4** - Reddit OAuth2 authentication for bypassing datacenter IP blocks, token caching and auto-refresh
- **v0.9.3** - Thread safety improvements with actor-based stores, GitLab/Codeberg token support, SSL bypass acknowledgment, improved Reddit fallback behavior, expanded YouTube URL patterns
- **v0.9.0** - Structured configuration required (sub-configs replace flat params), Cache is now a class with singleton, Reddit cache helpers moved to Reddit module, readability improvements
- **v0.8.3** - Fixed RSS 2.0 `<comments>` element extraction, fixed streaming parser bugs
- **v0.8.0** - Added comment_url, commentary_url, is_discussion_url fields, LinkResolver module
- **v0.4.0** - Structured error handling, SourceType enum, rate limiting, enhanced security
- **v0.3.0** - Added content extraction, JSON Feed support, RequestConfig
- **v0.2.1** - Bug fixes and cleanup
- **v0.2.0** - Functional rewrite
- **v0.1.1** - Dependency fixes
- **v0.1.0** - Initial release
