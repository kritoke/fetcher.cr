---
priority: MED
labels: [memory, gc]
created: 2026-05-29
affected_files:
  - src/fetcher/entry.cr
---

# Entry.categories and Entry.attachments allocate empty arrays per entry (LOW)

## Problem

Each `Entry` record allocates fresh `Array(String)` and `Array(Attachment)` instances even when empty:

```crystal
# entry.cr:7-8
categories : Array(String) = [] of String,
attachments : Array(Attachment) = [] of Attachment,
```

With thousands of entries that have no categories or attachments, these empty array allocations add up (~16 bytes per empty Array × 2 × n entries).

## Root Cause

Record fields initialize to empty array literals, creating a new instance per Entry.

## Suggested Fix

Use `Nil` for truly optional collections:

```crystal
record Entry,
  ...,
  categories : Array(String)? = nil,
  attachments : Array(Attachment)? = nil,
  ...
end
```

Caller must handle `nil` case, but avoids allocation.

## Alternative: Singleton empty arrays

```crystal
EMPTY_STRING_ARRAY = [] of String
EMPTY_ATTACHMENT_ARRAY = [] of Attachment

record Entry,
  ...,
  categories : Array(String) = EMPTY_STRING_ARRAY,
  attachments : Array(Attachment) = EMPTY_ATTACHMENT_ARRAY,
  ...
end
```

This reuses the same empty array instance across all entries.

## Impact

- LOW: ~32 bytes × n entries with no categories/attachments
- 10,000 entries = ~320KB of unnecessary allocation
- GC pressure increase is minimal

## Status

Nice to have, not critical. Consider for future optimization pass.