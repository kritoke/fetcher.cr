# Fetcher

A standalone Crystal library for fetching RSS feeds, Reddit posts, and software release data.

## Features

- **RSS/Atom Feeds** - Standard RSS and Atom feed parsing
- **Reddit** - Fetch posts from subreddits  
- **Software Releases** - Track GitHub, GitLab, and Codeberg releases
- **Automatic Driver Detection** - Automatically selects the right parser based on URL
- **Caching Support** - ETag and Last-Modified header support
- **Retry Logic** - Built-in retry with exponential backoff
- **Connection Pooling** - Reusable HTTP clients for better performance

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  fetcher:
    github: kritoke/fetcher.cr
    version: "~> 0.1"
```

## Usage

```crystal
require "fetcher"

# Simple fetch
result = Fetcher::Fetcher.pull("https://example.com/feed.xml")

case result
in Success(data)
  puts data.title
  data.items.each { |item| puts item.title }
in Failure(error)
  puts "Error: #{error.message}"
end
```

### With Caching Headers

```crystal
result = Fetcher::Fetcher.pull(
  "https://example.com/feed.xml",
  HTTP::Headers.new,
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

result = Fetcher::Fetcher.pull("https://example.com/feed.xml", headers)
```

## Automatic Driver Detection

The library automatically detects the feed type based on the URL:

| URL Pattern | Driver |
|-------------|--------|
| `reddit.com/r/` | RedditDriver |
| `github.com/.../releases` | SoftwareDriver |
| `gitlab.com/.../-/releases` | SoftwareDriver |
| `codeberg.org/.../releases` | SoftwareDriver |
| All others | RSSDriver |

## Configuration

### Custom Logger

```crystal
Fetcher.logger = ->(msg : String) { puts "[Fetcher] #{msg}" }
```

## Development

```bash
crystal deps
crystal spec
```

## License

MIT
