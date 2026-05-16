require "spec"
require "../src/fetcher"

describe Fetcher::Cache do
  it "creates instance-local stores separate from class store" do
    # Ensure instance cache does not share entries with class-level store
    Fetcher::Cache.clear
    inst = Fetcher::Cache.new(10, true)
    inst.set("foo", Fetcher::Result.builder.entries([] of Fetcher::Entry).build, 1.minute)

    Fetcher::Cache.get("foo").should be_nil
  end

  it "allows injecting a shared CacheStore into instances" do
    store = Fetcher::CacheStore.new(10, true)
    inst1 = Fetcher::Cache.new(10, true, store)
    inst2 = Fetcher::Cache.new(10, true, store)

    inst1.set("shared", Fetcher::Result.builder.entries([] of Fetcher::Entry).build, 1.minute)
    Fetcher::Cache.get("shared").should be_nil
    inst2.get("shared").should_not be_nil
  end
end
