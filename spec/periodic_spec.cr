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
    timeout = Time.utc + 1.second
    loop do
      break if called || Time.utc > timeout
      sleep 0.01
    end

    called.should be_true
  end
end
