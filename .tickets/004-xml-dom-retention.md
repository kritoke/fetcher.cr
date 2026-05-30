---
priority: MED
labels: [memory, gc, performance]
created: 2026-05-29
affected_files:
  - src/fetcher/rss_parser.cr
  - src/fetcher/json_feed_parser.cr
  - src/fetcher/xml_streaming_parser.cr
---

# XML Document retention during feed parsing (MED)

## Problem

`RSSParser.parse_xml` builds the **full DOM** in memory for each feed:

```crystal
# rss_parser.cr:47-57
private def parse_xml(data : String) : XML::Document
  XML.parse(data, options: XML::ParserOptions::RECOVER |
                           XML::ParserOptions::NONET |
                           XML::ParserOptions::NOBLANKS |
                           XML::ParserOptions::NODICT)
end
```

For feeds with large enclosures or inline CDATA, the DOM can be **several MB**. The `XML::Document` is held in memory until `parse_entries` returns.

## Root Cause

- `XML.parse` builds complete tree structure
- Each text node becomes a separate String allocation
- DOM persists until method returns
- Large feeds (100+ items with enclosures) create significant pressure

## Current Alternatives

- `XMLStreamingParser` uses `XML::Reader` (event-based, no DOM)
- `StreamingRSSParser` also exists for large feeds

## Suggested Fixes

### Option A: Explicit DOM release
```crystal
def parse_all(data : String, limit : Int32) : Tuple(Array(Entry), FeedMetadata)
  xml = parse_xml(data)
  entries = parse_entries(xml, limit)
  metadata = parse_feed_metadata(xml)
  # Explicitly release DOM before returning
  xml = nil
  GC.collect  # Optional: force collection if memory critical
  {entries, metadata}
end
```

### Option B: Prefer streaming parser
Document that for large feeds (>50 items), `XMLStreamingParser` should be used instead of `RSSParser`.

### Option C: Size-based parser selection
```crystal
def parse_entries(data : String, limit : Int32) : Array(Entry)
  if data.bytesize > 1_000_000  # 1MB threshold
    XMLStreamingParser.parse_entries(data, limit)
  else
    RSSParser.new.parse_entries(data, limit)
  end
end
```

## Notes

- Streaming parsers are available but not used by default
- DOM parsing is simpler and more maintainable
- For typical feed sizes (<100KB), this is not a problem

## Status

Known limitation. Streaming parsers exist as alternative.