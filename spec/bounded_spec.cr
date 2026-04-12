require "spec"
require "time"
require "../src/fetcher/bounded_registry"

struct TestEntry
  getter last_accessed : Time
  getter ttl : Time::Span

  def initialize(@last_accessed : Time, @ttl : Time::Span); end
end

describe Fetcher::BoundedRegistry do
  it "cleans up expired entries" do
    now = Time.utc
    entries = {
      "a" => TestEntry.new(now - 3600.seconds, 30.seconds),
      "b" => TestEntry.new(now, 30.seconds)
    }

    Fetcher::BoundedRegistry.cleanup(entries)

    entries.size.should eq 1
    entries.has_key?("b").should be_true
  end

  it "ensures limit by evicting oldest entries" do
    entries = {} of String => TestEntry
    0.upto(5) do |i|
      entries[i.to_s] = TestEntry.new(Time.utc - (i * 60).seconds, 60.minutes)
    end

    # enforce limit to 3 entries
    Fetcher::BoundedRegistry.ensure_limit(entries, 3, 60.minutes)
    entries.size.should be <= 3
  end

  
end
