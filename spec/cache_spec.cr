require "spec"
require "../src/fetcher"

describe "Fetcher::Cache" do
  before_each do
    Fetcher::Cache.clear
    Fetcher::Cache.enabled = true
    Fetcher::Cache.max_size = 100
  end

  describe "get and set" do
    it "returns nil for non-existent key" do
      result = Fetcher::Cache.get("nonexistent")
      result.should be_nil
    end

    it "stores and retrieves a result" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("test_key", result, 5.minutes)

      cached = Fetcher::Cache.get("test_key")
      cached.should_not be_nil
      cached.try(&.site_link).should eq("https://example.com")
    end

    it "updates existing entry" do
      result1 = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example1.com")
      result2 = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example2.com")

      Fetcher::Cache.set("test_key", result1, 5.minutes)
      Fetcher::Cache.set("test_key", result2, 5.minutes)

      cached = Fetcher::Cache.get("test_key")
      cached.should_not be_nil
      cached.try(&.site_link).should eq("https://example2.com")
    end
  end

  describe "LRU eviction" do
    it "evicts least recently used entry when max size is reached" do
      Fetcher::Cache.max_size = 3

      3.times do |i|
        result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example#{i}.com")
        Fetcher::Cache.set("key#{i}", result, 5.minutes)
      end

      Fetcher::Cache.get("key0")

      new_result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://new.com")
      Fetcher::Cache.set("key3", new_result, 5.minutes)

      Fetcher::Cache.get("key0").should_not be_nil
      Fetcher::Cache.get("key1").should be_nil
    end

    it "respects max_size configuration" do
      Fetcher::Cache.max_size = 2

      5.times do |i|
        result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example#{i}.com")
        Fetcher::Cache.set("key#{i}", result, 5.minutes)
      end

      Fetcher::Cache.get("key0").should be_nil
      Fetcher::Cache.get("key1").should be_nil
      Fetcher::Cache.get("key3").should_not be_nil
    end
  end

  describe "TTL expiration" do
    it "returns nil for expired entry" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("test_key", result, 1.millisecond)

      sleep 10.milliseconds

      cached = Fetcher::Cache.get("test_key")
      cached.should be_nil
    end

    it "does not return expired entry even if recently accessed" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("test_key", result, 1.millisecond)

      sleep 5.milliseconds
      Fetcher::Cache.get("test_key")

      sleep 5.milliseconds
      cached = Fetcher::Cache.get("test_key")
      cached.should be_nil
    end
  end

  describe "cache statistics" do
    it "tracks hits and misses" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("test_key", result, 5.minutes)

      Fetcher::Cache.get("nonexistent")
      Fetcher::Cache.get("test_key")
      Fetcher::Cache.get("test_key")

      stats = Fetcher::Cache.stats
      stats.hits.should eq(2)
      stats.misses.should eq(1)
    end

    it "tracks evictions" do
      Fetcher::Cache.max_size = 2

      5.times do |i|
        result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example#{i}.com")
        Fetcher::Cache.set("key#{i}", result, 5.minutes)
      end

      stats = Fetcher::Cache.stats
      stats.evictions.should eq(3)
    end

    it "calculates hit ratio" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("test_key", result, 5.minutes)

      9.times { Fetcher::Cache.get("test_key") }
      Fetcher::Cache.get("nonexistent")

      stats = Fetcher::Cache.stats
      stats.hit_ratio.should eq(0.9)
    end
  end

  describe "clear" do
    it "removes all entries" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("key1", result, 5.minutes)
      Fetcher::Cache.set("key2", result, 5.minutes)

      Fetcher::Cache.clear

      Fetcher::Cache.get("key1").should be_nil
      Fetcher::Cache.get("key2").should be_nil
    end

    it "resets statistics" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("test_key", result, 5.minutes)
      Fetcher::Cache.get("test_key")

      Fetcher::Cache.clear

      stats = Fetcher::Cache.stats
      stats.hits.should eq(0)
      stats.misses.should eq(0)
    end
  end

  describe "clear_subreddit" do
    it "removes only entries for specified subreddit" do
      result1 = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      result2 = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")

      Fetcher::Cache.set("reddit:crystal:hot:25", result1, 5.minutes)
      Fetcher::Cache.set("reddit:news:hot:25", result2, 5.minutes)

      Fetcher::Reddit.clear_cache("crystal")

      Fetcher::Cache.get("reddit:crystal:hot:25").should be_nil
      Fetcher::Cache.get("reddit:news:hot:25").should_not be_nil
    end
  end

  describe "generate_cache_key" do
    it "generates correct cache key format" do
      key = Fetcher::Reddit.generate_cache_key("crystal", "hot", 25)
      key.should eq("reddit:crystal:hot:25")
    end
  end

  describe "ttl_for_sort" do
    it "returns 30 seconds for new posts" do
      Fetcher::Reddit.ttl_for_sort("new").should eq(30.seconds)
    end

    it "returns 30 seconds for rising posts" do
      Fetcher::Reddit.ttl_for_sort("rising").should eq(30.seconds)
    end

    it "returns 2 minutes for hot posts" do
      Fetcher::Reddit.ttl_for_sort("hot").should eq(2.minutes)
    end

    it "returns 10 minutes for top posts" do
      Fetcher::Reddit.ttl_for_sort("top").should eq(10.minutes)
    end

    it "returns 10 minutes for controversial posts" do
      Fetcher::Reddit.ttl_for_sort("controversial").should eq(10.minutes)
    end

    it "returns default TTL for unknown sort" do
      Fetcher::Reddit.ttl_for_sort("unknown").should eq(Fetcher::Cache::DEFAULT_TTL)
    end
  end

  describe "enabled toggle" do
    it "returns nil when disabled" do
      Fetcher::Cache.enabled = false
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("test_key", result, 5.minutes)

      cached = Fetcher::Cache.get("test_key")
      cached.should be_nil
    end

    it "stores entries when enabled" do
      Fetcher::Cache.enabled = true
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("test_key", result, 5.minutes)

      cached = Fetcher::Cache.get("test_key")
      cached.should_not be_nil
    end
  end
end
