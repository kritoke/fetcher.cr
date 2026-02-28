# Fetcher

A standalone Crystal library for fetching RSS feeds, Reddit posts, and software release data.

> ⚠️ **Unstable API**: This library is undergoing a major refactor (v0.2.0). The API may change significantly. Not recommended for production use until v1.0.0.

## Features

- **RSS/Atom Feeds** - Standard RSS and Atom feed parsing
- **Reddit** - Fetch posts from subreddits  
- **Software Releases** - Track GitHub, GitLab, and Codeberg releases
- **Automatic Driver Detection** - Automatically selects the right parser based on URL
- **Caching Support** - ETag and Last-Modified header support
- **Retry Logic** - Built-in retry with exponential backoff
- **Secure URL Detection** - Uses regex patterns to prevent domain spoofing

## Performance Notes

Connection pooling was removed in v0.2.0 for simplicity. Each request creates a new `HTTP::Client` instance. For most use cases this is fine, but high-frequency fetching may experience slight performance overhead from repeated TCP connections.

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  fetcher:
    github: kritoke/fetcher.cr
    version: "~> 0.2"
```

## Usage

```crystal
require "fetcher"

# Simple fetch (auto-detects feed type)
result = Fetcher.pull("https://example.com/feed.xml")

if error = result.error_message
  puts "Error: #{error}"
else
  result.entries.each { |entry| puts entry.title }
end
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
```

## Automatic Driver Detection

The library automatically detects the feed type based on the URL:

| URL Pattern | Driver |
|-------------|--------|
| `reddit.com/r/` | Reddit |
| `github.com/.../releases` | Software |
| `gitlab.com/.../-/releases` | Software |
| `codeberg.org/.../releases` | Software |
| All others | RSS |

## Result Structure

```crystal
record Result,
  entries : Array(Entry),
  etag : String?,
  last_modified : String?,
  site_link : String?,
  favicon : String?,
  error_message : String?

record Entry,
  title : String,
  url : String,
  content : String,
  author : String?,
  published_at : Time?,
  source_type : String,
  version : String?
```

## Development

```bash
crystal deps
crystal spec
```

## License

MIT
