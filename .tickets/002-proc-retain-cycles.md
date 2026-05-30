---
priority: MED
labels: [memory, gc, periodic-cleanup]
created: 2026-05-29
affected_files:
  - src/fetcher/periodic_cleanup.cr
  - src/fetcher/cache_store.cr
  - src/fetcher/circuit_breaker_store.cr
  - src/fetcher/rate_limiter_store.cr
---

# PeriodicCleanup Proc retain cycles prevent GC of abandoned stores (MED)

## Problem

Each store (CacheStore, CircuitBreakerStore, RateLimiterStore) creates a `Proc(Nil)` that captures `self`:

```crystal
# cache_store.cr:88
@cleanup_proc ||= Proc(Nil).new { cleanup }  # captures self

# periodic_cleanup.cr:7
@@registered_cleanups.add(cleanup)  # global holds proc forever
```

If a store instance is abandoned (no external references), the proc in `@@registered_cleanups` still holds a reference to the store via the captured `self`. This prevents the store from being garbage collected.

## Root Cause

- `PeriodicCleanup.register_cleanup` stores procs in a global `Set(Proc(Nil))` with no mechanism to unregister
- Stores register cleanup once (`@cleanup_registered` flag) but never unregister
- Proc captures `self` → global holds Proc → Proc holds self → circular reference

## Current Mitigation

Stores use `@cleanup_registered` to register **once** per store, not per-entry. This limits the leak to 1 proc per store instance, not O(n) procs. However, abandoned stores still leak.

## Suggested Fixes

### Option A: WeakRef (Crystal 1.5+)
```crystal
struct WeakCleanup
  getter ref : WeakRef(Object)
  
  def initialize(store : Object)
    @ref = WeakRef(Object).new(store)
  end
  
  def call
    obj = @ref.get
    obj.try(&.cleanup) if obj
  end
  
  def valid?
    @ref.get != nil
  end
end
```

### Option B: Store lifecycle management
Add explicit `shutdown` method to stores that unregisters cleanup:

```crystal
def shutdown : Nil
  PeriodicCleanup.unregister_cleanup { cleanup_proc.call }
  @cmd.close
end
```

### Option C: Accept the tradeoff
Document that stores should be reused (singleton pattern) rather than created per-use. The current `@cleanup_registered` pattern ensures only 1 proc per store type, not per instance.

## Notes

- This is a **theoretical** issue for typical usage (stores are singletons)
- Real memory growth comes from entries **inside** stores, not the stores themselves
- Implementing WeakRef may have performance overhead

## Status

Low priority. Document as known limitation if not fixed.