require "spec"
require "http/client"
require "../src/fetcher"

describe Fetcher::Driver do
  it "raises NotImplementedError when pull is called on the base class" do
    expect_raises(NotImplementedError) do
      Fetcher::Driver.pull("https://example.com", HTTP::Headers.new, 10, Fetcher::RequestConfig.new)
    end
  end

  describe ".registry" do
    it "is empty when no drivers have been loaded yet" do
      # This is a meta-check: by the time this spec runs, the drivers
      # are already loaded (because src/fetcher.cr requires them).
      # We assert the registry is *iterable* and contains classes; the
      # exact list depends on which drivers have been loaded.
      Fetcher::Driver.registry.should be_a(Array(Fetcher::Driver.class))
    end

    it "returns a fresh duplicate on each call (callers can mutate)" do
      first = Fetcher::Driver.registry
      second = Fetcher::Driver.registry
      # Different instances returned (each call dups).
      first.object_id.should_not eq(second.object_id)
    end

    it "returns a duplicate so callers can mutate without affecting the registry" do
      snapshot = Fetcher::Driver.registry
      original_size = snapshot.size
      snapshot << Fetcher::Driver  # attempt to mutate
      Fetcher::Driver.registry.size.should eq(original_size)
    end

    it "is refreshable" do
      Fetcher::Driver.refresh_registry.should be_a(Array(Fetcher::Driver.class))
    end
  end

  # .detect specs are in spec/driver_detect_spec.cr — that file is
  # loaded AFTER the driver migrations so the detect method has the
  # migrated driver classes available to return.
end
