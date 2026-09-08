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
    # Reuse the same Proc for both starts so the @@registered_cleanups
    # Set doesn't grow on each restart — that would inflate the observed
    # tick count regardless of whether the old fiber actually leaks.
    runs = Atomic.new(0)
    cleanup = -> { runs.add(1) }

    Fetcher::PeriodicCleanup.register_cleanup(&cleanup)
    Fetcher::PeriodicCleanup.start_periodic_cleanup(20.milliseconds, true, &cleanup)
    ::sleep 60.milliseconds

    # Force-restart. Old fiber must exit; only the new one should keep running.
    Fetcher::PeriodicCleanup.start_periodic_cleanup(20.milliseconds, true, &cleanup)

    # Reset and observe a 200ms window. Expected with one fiber ticking at
    # 20ms: ~10 invocations. With the leak bug (two fibers): ~20.
    runs.set(0)
    ::sleep 200.milliseconds
    observed = runs.get

    observed.should be > 0
    observed.should be < 15
  end
end
