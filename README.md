# Fetcher

A standalone Crystal library for fetching RSS feeds, Reddit posts, JSON Feeds, and software release data.

> ⚠️ **Unstable API**: This library is undergoing active development. The API may change until v1.0.0.

## Features

- **RSS/Atom Feeds** - Standard RSS and Atom feed parsing with content extraction
- **JSON Feed** - Full JSON Feed v1.1 support
- **Reddit** - Fetch posts from subreddits  
- **Software Releases** - Track GitHub, GitLab, and Codeberg releases
- **Content Extraction** - Extract full content, authors, categories, and attachments
- **Feed Metadata** - Extract feed-level information (title, description, language, authors)
- **Automatic Driver Detection** - Automatically selects the right parser based on URL
- **Caching Support** - ETag and Last-Modified header support
- **Retry Logic** - Built-in retry with exponential backoff
- **Configurable Timeouts** - Customize connection and read timeouts
- **HTTP Compression** - Automatic gzip/deflate support
- **Secure URL Detection** - Uses regex patterns to prevent domain spoofing

## Performance Notes

Connection pooling was removed in v0.2.0 for simplicity. Each request creates a new `HTTP::Client` instance. For most use cases this is fine, but high-frequency fetching may experience slight performance overhead from repeated TCP connections.

v0.3.0 adds configurable timeouts to handle slow feeds.

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  fetcher:
    github: kritoke/fetcher.cr
    version: "~> 0.3"
```

## Usage

### Simple Fetch

```crystal
require "fetcher"

# Simple fetch (auto-detects feed type - RSS, Atom, or JSON Feed)
result = Fetcher.pull("https://example.com/feed.xml")

if error = result.error_message
  puts "Error: #{error}"
else
  result.entries.each { |entry| puts entry.title }
end
```

### Accessing Extracted Content

```crystal
result = Fetcher.pull("https://example.com/feed.xml")

# Access feed-level metadata
puts "Feed: #{result.feed_title}" if result.feed_title
puts "Description: #{result.feed_description}" if result.feed_description

result.entries.each do |entry|
  # Basic fields (available in all versions)
  puts "Title: #{entry.title}"
  puts "URL: #{entry.url}"
  puts "Published: #{entry.published_at}" if entry.published_at
  
  # Rich content extraction (v0.3.0+)
  puts "Content: #{entry.content}" if !entry.content.empty?
  puts "Author: #{entry.author}" if entry.author
  puts "Categories: #{entry.categories.join(", ")}" unless entry.categories.empty?
  
  # Attachments (podcasts, downloads)
  entry.attachments.each do |att|
    puts "Attachment: #{att.url} (#{att.mime_type})"
    puts "Size: #{att.size_in_bytes / 1024}KB" if att.size_in_bytes
  end
end
```

### Custom Timeouts

```crystal
# Configure custom timeouts for slow feeds
config = Fetcher::RequestConfig.new(
  connect_timeout: 30.seconds,
  read_timeout: 60.seconds
)

result = Fetcher.pull("https://slow.example.com/feed.xml", config: config)
```

### With Caching Headers

```crystal
result = Fetcher.pull(
  "https://example.com/feed.xml",
  headers: HTTP::Headers.new,
  etag: "abc123",
  last_modified: "Wed, 01 Jan 2025 00:00:00 GMT",
  limit: 50
)
```

### Custom Headers

```crystal
headers = HTTP::Headers{
  "Authorization" => "Bearer token",
  "X-Custom" => "value"
}

result = Fetcher.pull("https://example.com/feed.xml", headers: headers)
```

### Explicit Driver Selection

```crystal
# Force a specific driver instead of auto-detection
result = Fetcher.pull_rss("https://example.com/feed.xml")
result = Fetcher.pull_reddit("https://reddit.com/r/crystal")
result = Fetcher.pull_software("https://github.com/crystal-lang/crystal/releases")
result = Fetcher.pull_json_feed("https://example.com/feed.json")
```

## Automatic Driver Detection

The library automatically detects the feed type based on the URL:

| URL Pattern | Driver |
|-------------|--------|
| `reddit.com/r/` | Reddit |
| `github.com/.../releases` | Software |
| `gitlab.com/.../-/releases` | Software |
| `codeberg.org/.../releases` | Software |
| `.json`, `/feed.json`, `/feeds/json` | JSON Feed |
| All others | RSS |

## Result Structure

### Result Record

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

record Author,
  name : String?,
  url : String?,
  avatar : String?
```

### Entry Record

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

## Supported Feed Formats

### RSS 2.0
- Standard RSS 2.0 elements (title, link, description, pubDate)
- Content-encoded module (`content:encoded`)
- Dublin Core (`dc:creator` for author)
- Enclosures (podcasts, downloads)
- Categories
- RSS 1.0/RDF (basic support)

### Atom 1.0
- Standard Atom elements (title, link, published, updated)
- Content element (HTML, text, xhtml types)
- Summary element
- Author element (name, uri)
- Categories (term attribute)

### JSON Feed 1.0/1.1
- Full JSON Feed v1.0 and v1.1 support
- `content_html` and `content_text`
- `authors` array (feed and item level)
- `tags` as categories
- `attachments` for podcasts/media
- `date_published` and `date_modified`
- Feed metadata (title, description, language, icon, favicon)

## Development

```bash
crystal deps
crystal spec  # 93 tests
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create a new Pull Request

## License

MIT
