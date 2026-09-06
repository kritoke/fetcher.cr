require "spec"
require "time"
require "../src/fetcher/periodic_cleanup"

describe Fetcher::PeriodicCleanup do
  it "calls cleanup periodically" do
    called = false
    # start a very short interval cleanup; use force to ensure it starts in test
    Fetcher::PeriodicCleanup.start_periodic_cleanup(10.milliseconds, true) do
      called = true
    end

    # wait up to 1 second for the cleanup to be called
    timeout = Time.instant + 1.second
    loop do
      break if called || Time.instant > timeout
      ::sleep 0.01.seconds
    end

    called.should be_true
  end

  it "stops the previous fiber on restart so it doesn't run stale cleanups" do
    # Register a single cleanup via the public API. With the leak bug, the
    # old fiber would keep running after restart, so the cleanup would
    # fire at 2x the rate. With the fix, exactly one fiber is alive and
    # the rate matches the interval.
    runs = Atomic.new(0)

    Fetcher::PeriodicCleanup.register_cleanup do
      runs.add(1)
    end

    # Force-start so we know one fiber is alive.
    Fetcher::PeriodicCleanup.start_periodic_cleanup(20.milliseconds, true) { runs.add(1) }
    ::sleep 60.milliseconds

    # Force-restart. Old fiber must exit; only the new one should keep running.
    Fetcher::PeriodicCleanup.start_periodic_cleanup(20.milliseconds, true) { runs.add(1) }

    # Reset and observe a 200ms window. Expected with one fiber: ~10 invocations.
    # With the bug (two fibers): ~20.
    runs.set(0)
    ::sleep 200.milliseconds
    observed = runs.get

    # Each of the two registered cleanups fires per tick, so with one
    # fiber at 20ms for 200ms we expect ~20 invocations (10 ticks × 2 cleanups).
    # With a leaked second fiber we'd see ~40. Bound it well below that.
    observed.should be > 0
    observed.should be < 30
  end
end
