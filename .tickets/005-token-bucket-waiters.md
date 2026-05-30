---
priority: LOW
labels: [memory, gc]
created: 2026-05-29
affected_files:
  - src/fetcher/token_bucket_rate_limiter.cr
---

# TokenBucketRateLimiter waiter array growth under burst load (LOW)

## Problem

`@waiters` array grows with every `acquire` call when tokens are insufficient:

```crystal
# token_bucket_rate_limiter.cr:40
@waiters = [] of Tuple(Float64, Channel(QueueFullError?))
```

Fibers are blocked via their `Channel(QueueFullError?)`, and `@waiters` holds references to all blocked channels. Under burst requests, the array accumulates.

## Root Cause

- Array grows unbounded within `@max_waiters` limit
- Array not actively reduced except via `TickMsg` processing
- `@pending_wakeup` fiber holds reference until wakeup fires or is cancelled

## Impact

- LOW: Bounded by `@max_waiters` (default 1000)
- 1000 × (Float64 + Channel reference) ≈ 8KB baseline
- Under sustained burst, waiter array holds 1000 entries

## Suggested Fix

No fix needed — behavior is correct:
- `@max_waiters` provides hard upper bound
- `QueueFullError` returned when limit reached
- Array shrinks as waiters complete

## Status

Acceptable. Document as expected behavior.

---

## Priority Summary

| Ticket | Priority | Impact | Status |
|--------|----------|--------|--------|
| 001-entry-content-memory | HIGH | 250-500MB peak | Needs implementation |
| 002-proc-retain-cycles | MED | Theoretical | Acceptable tradeoff |
| 003-empty-arrays-per-entry | LOW | ~320KB/10k entries | Nice to have |
| 004-xml-dom-retention | MED | Several MB/large feed | Streaming alternative exists |
| 005-token-bucket-waiters | LOW | 8KB baseline | Acceptable |