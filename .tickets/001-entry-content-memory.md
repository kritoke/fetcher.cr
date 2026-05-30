---
priority: HIGH
labels: [memory, gc, performance]
created: 2026-05-29
affected_files:
  - src/fetcher/entry.cr
  - src/fetcher/entry_factory.cr
  - src/fetcher/rss_parser.cr
  - src/fetcher/json_feed_parser.cr
---

# Entry.content holds full HTML strings during processing (MEDIUM-HIGH)

## Problem

`Entry.content` holds the **entire** HTML or text content of feed items (20-200KB per entry). During the parsing pipeline:

1. `RSSParser.parse_entries` extracts full content per item
2. `EntryFactory.sanitize(content)` creates **additional** String allocations
3. Entries are held in `Result.entries` array
4. Caller may only need `title`, `url`, `published_at` but pays full memory cost

With 100+ entries × 50KB content = **5-10MB** spike per feed, 50 concurrent feeds = **250-500MB** peak allocation.

## Root Cause

- `Entry.record` includes `content : String = ""` 
- `EntryFactory.create` calls `sanitize(content)` unconditionally
- No option to skip content extraction

## Suggested Fixes

### Option A: Content stripping flag (preferred)
Add `strip_content : Bool = false` parameter to `Entry.create` and parsers:

```crystal
def self.create(
  ..., 
  strip_content : Bool = false,
) : Entry
  Entry.new(
    ...,
    content: strip_content ? "" : sanitize(content),
  )
end
```

Update calling code to use `strip_content: true` when only metadata is needed.

### Option B: Lazy content
Store content as `Proc(String)?` that can be discarded after use. More complex but avoids carrying unused data.

### Option C: Config flag
Add `include_content : Bool = true` to `RequestConfig` so callers can opt out.

## Notes

- Boehm GC (Crystal's default) never returns memory to OS — peak allocation persists
- Content is only needed for article display, not for feed metadata
- RSS `description` field often contains truncated content anyway

## Status

Needs investigation and implementation.