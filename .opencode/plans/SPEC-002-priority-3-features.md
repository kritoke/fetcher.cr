# Fetcher.cr v0.3.0 - Feature Expansion Specification

## Specification ID: SPEC-002
## Status: Planning Phase
## Priority: High
## Created: 2026-03-01
## Target Branch: `feature/priority-3-content-extraction`

---

## Overview

This specification tracks major feature additions to Fetcher.cr to make it production-ready. After completing Priority 1 & 2 (linting fixes and DRY refactoring), we now focus on extracting meaningful content from feeds and supporting modern formats.

**Branch Strategy:**
- Create branch: `feature/priority-3-content-extraction` ✓
- Work in isolated feature branches per phase
- Merge to main only after comprehensive testing
- Target version: v0.3.0 (minor version bump due to new features)

---

## Phase 1: Content & Author Extraction (High Priority)

### 1.1 RSS Content Extraction

**Problem:**
Currently `Entry.content` is always empty string `""`. RSS 2.0 and Atom feeds contain rich content that should be extracted.

**RSS 2.0 Elements to Extract:**
- `<description>` - Summary or full content
- `<content:encoded>` - Full HTML content (common in WordPress)
- `<dc:creator>` - Author name (Dublin Core)
- `<author>` - Author email (RSS 2.0, less useful)
- `<media:content>` - Media attachments (images, videos)
- `<enclosure>` - Podcast/file attachments

**Atom Elements to Extract:**
- `<summary>` - Brief description
- `<content>` - Full content (can be plain text, HTML, or XHTML)
- `<author><name>` - Author name
- `<author><uri>` - Author URL
- `<category>` - Tags/categories

**Implementation Plan:**

```crystal
# Update Entry record to support extracted fields
record Entry,
  title : String,
  url : String,
  source_type : String,
  content : String = "",              # Now populated from description/content:encoded
  content_html : String? = nil,       # HTML version if different from content
  author : String? = nil,             # Now extracted from dc:creator/author
  author_url : String? = nil,         # Author's URL from Atom author/uri
  published_at : Time? = nil,
  categories : Array(String) = [] of String,  # New: tags/categories
  attachments : Array(Attachment) = [] of Attachment,  # New: enclosures/media
  version : String? = nil
```

**New Record Type:**
```crystal
record Attachment,
  url : String,
  mime_type : String,
  title : String? = nil,
  size_in_bytes : Int64? = nil,
  duration_in_seconds : Int32? = nil
```

**RSS Parsing Changes:**
```crystal
private def self.parse_rss_item(node : XML::Node) : Entry
  # Existing title/link extraction...
  
  # NEW: Content extraction
  description = node.xpath_node("./*[local-name()='description']").try(&.text)
  content_encoded = node.xpath_node("./*[local-name()='encoded']").try(&.text) # content: namespace
  content = content_encoded || description || ""
  
  # NEW: Author extraction
  dc_creator = node.xpath_node("./*[local-name()='creator']").try(&.text) # dc: namespace
  author = dc_creator
  
  # NEW: Categories
  categories = node.xpath_nodes("./*[local-name()='category']").map(&.text).compact
  
  # NEW: Enclosures
  attachments = node.xpath_nodes("./*[local-name()='enclosure']").compact_map do |enc|
    url = enc["url"]?
    type = enc["type"]?
    length = enc["length"]?.try(&.to_i64)
    next unless url && type
    
    Attachment.new(url: url, mime_type: type, size_in_bytes: length)
  end
  
  Entry.create(
    title: title,
    url: link,
    source_type: "rss",
    content: content.strip,
    author: author,
    published_at: pub_date,
    categories: categories,
    attachments: attachments
  )
end
```

---

### 1.2 Atom Content Extraction

**Implementation:**
```crystal
private def self.parse_atom_entry(node : XML::Node) : Entry
  # Existing title/link extraction...
  
  # NEW: Content/summary
  content_node = node.xpath_node("./*[local-name()='content']")
  summary_node = node.xpath_node("./*[local-name()='summary']")
  
  content_type = content_node.try(&.[]?("type")) || "text"
  content = case content_type
            when "html", "xhtml" then content_node.try(&.text) || ""
            when "text" then content_node.try(&.text) || ""
            else summary_node.try(&.text) || ""
            end
  
  # NEW: Author
  author_node = node.xpath_node("./*[local-name()='author']")
  author_name = author_node.try(&.xpath_node("./*[local-name()='name']").try(&.text))
  author_uri = author_node.try(&.xpath_node("./*[local-name()='uri']").try(&.text))
  
  # NEW: Categories
  categories = node.xpath_nodes("./*[local-name()='category']").compact_map(&.[]?("term"))
  
  Entry.create(...)
end
```

---

### 1.3 Testing Requirements

**Unit Tests:**
- [ ] RSS with description only
- [ ] RSS with content:encoded (WordPress style)
- [ ] RSS with dc:creator author
- [ ] RSS with enclosures (podcasts)
- [ ] RSS with categories
- [ ] Atom with summary only
- [ ] Atom with content (HTML)
- [ ] Atom with author name/uri
- [ ] Atom with categories
- [ ] Mixed content types

**Sample Data Files:**
- `test/fixtures/rss_wordpress.xml` - WordPress-style feed with content:encoded
- `test/fixtures/rss_podcast.xml` - Podcast feed with enclosures
- `test/fixtures/atom_full.xml` - Full-featured Atom feed
- `test/fixtures/atom_microblog.xml` - Minimal Atom feed

---

## Phase 2: JSON Feed Support (High Priority)

### 2.1 JSON Feed Parser

**Why JSON Feed:**
- Modern alternative to RSS/Atom
- Simpler JSON format (no XML parsing)
- Growing adoption (Micro.blog, Daring Fireball, etc.)
- Better suited for programmatic consumption

**Driver Detection:**
```crystal
def self.detect_driver(url : String) : DriverType
  # ... existing checks ...
  if url.ends_with?(".json") || url.includes?("/feed.json")
    # Check Content-Type header for application/feed+json
    DriverType::JSONFeed
  end
end
```

**JSON Feed Structure:**
```crystal
module Fetcher
  module JSONFeed
    def self.pull(url : String, headers : HTTP::Headers, limit : Int32 = 100) : Result
      response = HTTPClient.fetch(url, headers)
      
      case response.status_code
      when 304
        Result.success(entries: [] of Entry, etag: response.headers["ETag"]?)
      when 200
        parse_feed(response.body, limit)
      when 500..599
        raise RetriableError.new("Server error: #{response.status_code}")
      else
        Result.error("HTTP #{response.status_code}")
      end
    end
    
    private def self.parse_feed(body : String, limit : Int32) : Result
      parsed = JSON.parse(body)
      
      # Validate JSON Feed structure
      version = parsed["version"]?.try(&.as_s)
      return Result.error("Invalid JSON Feed: missing version") unless version
      return Result.error("Unsupported JSON Feed version") unless version.includes?("https://jsonfeed.org/version/")
      
      # Extract feed metadata
      feed_title = parsed["title"]?.try(&.as_s) || "Untitled Feed"
      home_url = parsed["home_page_url"]?.try(&.as_s)
      feed_url = parsed["feed_url"]?.try(&.as_s)
      description = parsed["description"]?.try(&.as_s)
      favicon = parsed["favicon"]?.try(&.as_s)
      icon = parsed["icon"]?.try(&.as_s)
      
      # Parse items
      items = parsed["items"]?.try(&.as_a) || [] of JSON::Any
      entries = items.first(limit).compact_map { |item| parse_item(item) }
      
      Result.success(
        entries: entries,
        site_link: home_url,
        favicon: favicon || icon
      )
    end
    
    private def self.parse_item(item : JSON::Any) : Entry?
      id = item["id"]?.try(&.to_s) || return nil  # Required, must be unique
      url = item["url"]?.try(&.as_s) || id
      
      # Content: prefer HTML, fall back to text
      content_html = item["content_html"]?.try(&.as_s)
      content_text = item["content_text"]?.try(&.as_s)
      content = content_html || content_text || ""
      
      # Title
      title = item["title"]?.try(&.as_s)
      title = Entry.sanitize_title(title)
      
      # Author
      authors = item["authors"]?.try(&.as_a) || item["author"]?.try(&.as_a)
      author = authors.try(&.first?).try(&.["name"]?.try(&.as_s))
      author_url = authors.try(&.first?).try(&.["url"]?.try(&.as_s))
      
      # Date
      published = item["date_published"]?.try(&.as_s)
      modified = item["date_modified"]?.try(&.as_s)
      pub_date = TimeParser.parse_iso8601(published || modified)
      
      # Tags/categories
      tags = item["tags"]?.try(&.as_a).try(&.map(&.as_s)) || [] of String
      
      # Attachments
      attachments = item["attachments"]?.try(&.as_a).try(&.map do |att|
        Attachment.new(
          url: att["url"].as_s,
          mime_type: att["mime_type"].as_s,
          title: att["title"]?.try(&.as_s),
          size_in_bytes: att["size_in_bytes"]?.try(&.as_i64),
          duration_in_seconds: att["duration_in_seconds"]?.try(&.as_i)
        )
      end) || [] of Attachment
      
      # Featured image
      image = item["image"]?.try(&.as_s)
      banner = item["banner_image"]?.try(&.as_s)
      
      Entry.create(
        title: title,
        url: url,
        source_type: "jsonfeed",
        content: content,
        author: author,
        published_at: pub_date,
        categories: tags,
        attachments: attachments
      )
    end
  end
end
```

---

### 2.2 Integration with Main Fetcher

**Update src/fetcher.cr:**
```crystal
require "./fetcher/json_feed"

module Fetcher
  enum DriverType
    RSS
    Reddit
    Software
    JSONFeed  # NEW
  end
  
  def self.detect_driver(url : String, content_type : String? = nil) : DriverType
    # ... existing checks ...
    
    # Check for JSON Feed
    if content_type == "application/feed+json" || 
       content_type == "application/json" && (url.ends_with?(".json") || url.includes?("/feed.json"))
      DriverType::JSONFeed
    end
    
    DriverType::RSS  # fallback
  end
end
```

---

## Phase 3: Feed Metadata Extraction (Medium Priority)

### 3.1 Result Enhancement

**Add Feed Metadata to Result:**
```crystal
record Result,
  entries : Array(Entry),
  etag : String?,
  last_modified : String?,
  site_link : String?,
  favicon : String?,
  error_message : String?,
  # NEW: Feed-level metadata
  feed_title : String? = nil,
  feed_description : String? = nil,
  feed_language : String? = nil,
  feed_authors : Array(Author) = [] of Author
end

record Author,
  name : String?,
  url : String?,
  avatar : String?
```

**RSS Feed Metadata:**
```crystal
private def self.parse_rss(xml : XML::Node, limit : Int32) : Result
  channel = xml.xpath_node("//*[local-name()='channel']")
  
  site_link = resolve_rss_site_link(channel)
  feed_title = channel.try(&.xpath_node("./*[local-name()='title']").try(&.text))
  feed_description = channel.try(&.xpath_node("./*[local-name()='description']").try(&.text))
  feed_language = channel.try(&.xpath_node("./*[local-name()='language']").try(&.text))
  
  Result.success(
    entries: entries,
    site_link: site_link,
    favicon: favicon,
    feed_title: feed_title,
    feed_description: feed_description,
    feed_language: feed_language
  )
end
```

**JSON Feed Metadata:**
```crystal
private def self.parse_feed(body : String, limit : Int32) : Result
  parsed = JSON.parse(body)
  
  feed_title = parsed["title"]?.try(&.as_s)
  feed_description = parsed["description"]?.try(&.as_s)
  feed_language = parsed["language"]?.try(&.as_s)
  
  # Authors
  authors = parsed["authors"]?.try(&.as_a).try(&.map do |author|
    Author.new(
      name: author["name"]?.try(&.as_s),
      url: author["url"]?.try(&.as_s),
      avatar: author["avatar"]?.try(&.as_s)
    )
  end) || [] of Author
  
  Result.success(
    entries: entries,
    site_link: home_url,
    favicon: favicon || icon,
    feed_title: feed_title,
    feed_description: feed_description,
    feed_language: feed_language,
    feed_authors: authors
  )
end
```

---

## Phase 4: HTTP Improvements (Medium Priority)

### 4.1 Configurable Timeouts

**Current Issue:**
Hardcoded timeouts (10s connect, 30s read) may not suit all use cases.

**Solution:**
```crystal
module Fetcher
  record RequestConfig,
    connect_timeout : Time::Span = 10.seconds,
    read_timeout : Time::Span = 30.seconds,
    max_redirects : Int32 = 5,
    follow_redirects : Bool = true,
    ssl_verify : Bool = true
  
  def self.pull(url : String, 
                headers : HTTP::Headers = HTTP::Headers.new,
                limit : Int32 = 100,
                config : RequestConfig = RequestConfig.new) : Result
    # Pass config to HTTPClient
  end
end
```

**Update HTTPClient:**
```crystal
module HTTPClient
  def self.fetch(url : String, 
                 headers : HTTP::Headers,
                 config : RequestConfig = RequestConfig.new) : HTTP::Client::Response
    uri = URI.parse(url)
    client = HTTP::Client.new(uri)
    client.connect_timeout = config.connect_timeout
    client.read_timeout = config.read_timeout
    # Handle redirects, SSL, etc.
  end
end
```

---

### 4.2 HTTP Compression

**Add Accept-Encoding Header:**
```crystal
module Headers
  def self.build(custom_headers : HTTP::Headers = HTTP::Headers.new) : HTTP::Headers
    defaults = HTTP::Headers{
      "User-Agent"      => HTTPClient::DEFAULT_USER_AGENT,
      "Accept"          => HTTPClient::DEFAULT_ACCEPT_HEADER,
      "Accept-Language" => "en-US,en;q=0.9",
      "Accept-Encoding" => "gzip, deflate",  # NEW
      "Connection"      => "keep-alive",
    }
    defaults.merge!(custom_headers)
  end
end
```

**Handle Compressed Responses:**
Crystal's HTTP::Client handles gzip/deflate automatically, but we should verify and document this.

---

## Phase 5: Better Error Categorization (Medium Priority)

### 5.1 Error Types Hierarchy

**Current Issue:**
All errors return `error_message : String?`, making it hard to handle different error types programmatically.

**Proposed Error Types:**
```crystal
module Fetcher
  enum ErrorType
    NetworkError       # DNS, connection, timeout
    HTTPError          # 4xx, 5xx status codes
    ParseError         # Invalid XML/JSON
    NotFoundError      # 404
    RateLimited        # 429
    ServerError        # 5xx
    AuthenticationError # 401, 403
    UnsupportedFormat  # Unknown feed format
  end
  
  record Result,
    # ... existing fields ...
    error_type : ErrorType? = nil,
    error_code : Int32? = nil  # HTTP status code if applicable
end
```

**Usage:**
```crystal
result = Fetcher.pull("https://example.com/feed.xml")

if result.error_type
  case result.error_type
  when ErrorType::RateLimited
    # Implement backoff
  when ErrorType::NotFoundError
    # Notify user, don't retry
  when ErrorType::ParseError
    # Log malformed feed
  end
end
```

---

## Breaking Changes & Migration

### Version 0.3.0 Breaking Changes

1. **Entry record gains new fields** - Backward compatible (defaults provided)
2. **Result record gains new fields** - Backward compatible (defaults provided)
3. **HTTPClient.fetch signature changes** - May break direct usage
4. **JSON Feed driver added** - Detection logic updated

### Migration Guide

**No changes needed for:**
- Basic `Fetcher.pull(url)` usage
- Existing Entry/Result field access

**Updates needed for:**
- Direct `HTTPClient.fetch` calls (add config parameter)
- Pattern matching on `DriverType` enum (add JSONFeed case)

---

## Testing Strategy

### Unit Tests (Per Phase)

**Phase 1 Tests:**
- Content extraction from RSS 2.0
- Content extraction from Atom
- Author extraction (dc:creator, author/name)
- Category/tag extraction
- Enclosure/attachment parsing

**Phase 2 Tests:**
- JSON Feed v1.0 parsing
- JSON Feed v1.1 parsing
- JSON Feed with attachments
- JSON Feed author handling
- Content-type detection

**Phase 3 Tests:**
- RSS feed metadata
- Atom feed metadata
- JSON Feed metadata
- Multi-author feeds

**Phase 4 Tests:**
- Custom timeout behavior
- Compression handling
- Redirect following

**Phase 5 Tests:**
- Error type categorization
- HTTP error mapping

### Integration Tests

- Real feed parsing (use public feeds)
- Error handling with mock servers
- Performance benchmarks

### Fixture Files

```
test/
  fixtures/
    rss_wordpress.xml
    rss_podcast.xml
    atom_full.xml
    atom_minimal.xml
    jsonfeed_v1.json
    jsonfeed_v1.1.json
    jsonfeed_podcast.json
```

---

## Implementation Timeline

### Phase 1: Content & Author Extraction (2-3 weeks)
- Week 1: RSS content/author extraction
- Week 2: Atom content/author extraction
- Week 3: Testing and bug fixes

### Phase 2: JSON Feed Support (2 weeks)
- Week 1: JSON Feed parser implementation
- Week 2: Integration and testing

### Phase 3: Feed Metadata (1 week)
- Week 1: Result enhancement, metadata extraction

### Phase 4: HTTP Improvements (1-2 weeks)
- Week 1: Configurable timeouts
- Week 2: Compression and redirects

### Phase 5: Error Categorization (1 week)
- Week 1: Error type system implementation

**Total: 7-9 weeks**

---

## Success Metrics

- [ ] 90%+ test coverage for new features
- [ ] All existing tests pass (41 examples)
- [ ] Zero Ameba issues
- [ ] Support 10+ real-world feeds per format
- [ ] Documentation updated with examples
- [ ] Migration guide complete
- [ ] Performance within 10% of v0.2.1

---

## Open Questions

1. **Content field strategy:**
   - Single `content` field with HTML?
   - Separate `content` and `content_html` fields?
   - Add `content_text` for plain text?

2. **Author field naming:**
   - Keep `author : String?` for name only?
   - Change to `author : Author?` record?
   - Add both for flexibility?

3. **JSON Feed version handling:**
   - Support both v1 and v1.1?
   - Require specific version?

4. **Backward compatibility:**
   - Deprecate old patterns or support indefinitely?
   - Version the API?

---

## References

- [JSON Feed Spec v1.1](https://www.jsonfeed.org/version/1.1/)
- [RSS 2.0 Spec](http://cyber.harvard.edu/rss/rss.html)
- [Atom Spec (RFC 4287)](https://tools.ietf.org/html/rfc4287)
- [Media RSS](https://www.rssboard.org/media-rss)
- [Dublin Core](https://www.dublincore.org/specifications/dublin-core/)

---

## Appendix: Example Usage After Implementation

```crystal
require "fetcher"

# Fetch a blog feed with content
result = Fetcher.pull("https://example.com/feed.xml")

if result.feed_title
  puts "Feed: #{result.feed_title}"
  puts "Description: #{result.feed_description}"
end

result.entries.each do |entry|
  puts "\n#{entry.title}"
  puts "By #{entry.author}" if entry.author
  puts "Published: #{entry.published_at}" if entry.published_at
  puts "Categories: #{entry.categories.join(", ")}" unless entry.categories.empty?
  
  # Content
  puts entry.content if entry.content && !entry.content.empty?
  
  # Attachments (podcasts, images, etc.)
  entry.attachments.each do |att|
    puts "Attachment: #{att.url} (#{att.mime_type})"
    puts "Size: #{att.size_in_bytes / 1024}KB" if att.size_in_bytes
  end
end

# Fetch JSON Feed
result = Fetcher.pull("https://example.com/feed.json")
# Same API, automatic detection

# Custom timeout for slow feeds
result = Fetcher.pull(
  "https://slow.example.com/feed.xml",
  config: Fetcher::RequestConfig.new(connect_timeout: 30.seconds)
)

# Error handling with types
result = Fetcher.pull("https://example.com/feed.xml")
if result.error_type
  case result.error_type
  when Fetcher::ErrorType::RateLimited
    puts "Rate limited, waiting..."
    sleep 60
  when Fetcher::ErrorType::NotFoundError
    puts "Feed not found"
  end
end
```

---

## Sign-off

**Created:** 2026-03-01  
**Author:** Code Review & Planning  
**Status:** Ready for Implementation  
**Target Version:** v0.3.0  
**Branch:** `feature/priority-3-content-extraction`
