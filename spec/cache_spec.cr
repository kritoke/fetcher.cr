require "spec"
require "../src/fetcher"

describe "Fetcher::Cache" do
  describe "get and set" do
    it "returns nil for non-existent key" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result = cache.get("nonexistent")
      result.should be_nil
    end

    it "stores and retrieves a result" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      cache.set("test_key", result, 5.minutes)

      cached = cache.get("test_key")
      cached.should_not be_nil
      cached.try(&.site_link).should eq("https://example.com")
    end

    it "updates existing entry" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result1 = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example1.com")
      result2 = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example2.com")

      cache.set("test_key", result1, 5.minutes)
      cache.set("test_key", result2, 5.minutes)

      cached = cache.get("test_key")
      cached.should_not be_nil
      cached.try(&.site_link).should eq("https://example2.com")
    end
  end

  describe "LRU eviction" do
    it "evicts least recently used entry when max size is reached" do
      cache = Fetcher::Cache.new(max_size: 3, enabled: true)

      3.times do |i|
        result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example#{i}.com")
        cache.set("key#{i}", result, 5.minutes)
      end

      cache.get("key0")

      new_result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://new.com")
      cache.set("key3", new_result, 5.minutes)

      cache.get("key0").should_not be_nil
      cache.get("key1").should be_nil
    end

    it "respects max_size configuration" do
      cache = Fetcher::Cache.new(max_size: 2, enabled: true)

      5.times do |i|
        result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example#{i}.com")
        cache.set("key#{i}", result, 5.minutes)
      end

      cache.get("key0").should be_nil
      cache.get("key1").should be_nil
      cache.get("key3").should_not be_nil
    end
  end

  describe "TTL expiration" do
    it "returns nil for expired entry" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      cache.set("test_key", result, 1.millisecond)

      sleep 10.milliseconds

      cached = cache.get("test_key")
      cached.should be_nil
    end

    it "does not return expired entry even if recently accessed" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      cache.set("test_key", result, 1.millisecond)

      sleep 5.milliseconds
      cache.get("test_key")

      sleep 5.milliseconds
      cached = cache.get("test_key")
      cached.should be_nil
    end
  end

  describe "cache statistics" do
    it "tracks hits and misses" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      cache.set("test_key", result, 5.minutes)

      cache.get("nonexistent")
      cache.get("test_key")
      cache.get("test_key")

      stats = cache.stats
      stats.hits.should eq(2)
      stats.misses.should eq(1)
    end

    it "tracks evictions" do
      cache = Fetcher::Cache.new(max_size: 2, enabled: true)

      5.times do |i|
        result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example#{i}.com")
        cache.set("key#{i}", result, 5.minutes)
      end

      stats = cache.stats
      stats.evictions.should eq(3)
    end

    it "calculates hit ratio" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      cache.set("test_key", result, 5.minutes)

      9.times { cache.get("test_key") }
      cache.get("nonexistent")

      stats = cache.stats
      stats.hit_ratio.should eq(0.9)
    end
  end

  describe "clear" do
    it "removes all entries" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      cache.set("key1", result, 5.minutes)
      cache.set("key2", result, 5.minutes)

      cache.clear

      cache.get("key1").should be_nil
      cache.get("key2").should be_nil
    end

    it "resets statistics" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      cache.set("test_key", result, 5.minutes)
      cache.get("test_key")

      cache.clear

      stats = cache.stats
      stats.hits.should eq(0)
      stats.misses.should eq(0)
    end
  end

  describe "clear_by_prefix" do
    it "removes only entries for specified prefix" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result1 = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      result2 = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")

      cache.set("reddit:crystal:hot:25", result1, 5.minutes)
      cache.set("reddit:news:hot:25", result2, 5.minutes)

      cache.clear_by_prefix("reddit:crystal:")

      cache.get("reddit:crystal:hot:25").should be_nil
      cache.get("reddit:news:hot:25").should_not be_nil
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
      cache = Fetcher::Cache.new(max_size: 100, enabled: false)
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      cache.set("test_key", result, 5.minutes)

      cached = cache.get("test_key")
      cached.should be_nil
    end

    it "stores entries when enabled" do
      cache = Fetcher::Cache.new(max_size: 100, enabled: true)
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      cache.set("test_key", result, 5.minutes)

      cached = cache.get("test_key")
      cached.should_not be_nil
    end
  end

  describe "backward-compatible class methods" do
    before_each do
      Fetcher::Cache.default.clear
      Fetcher::Cache.default.enabled = true
      Fetcher::Cache.default.max_size = 100
    end

    it "Cache.get delegates to default instance" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("test_key", result, 5.minutes)

      cached = Fetcher::Cache.get("test_key")
      cached.should_not be_nil
      cached.try(&.site_link).should eq("https://example.com")
    end

    it "Cache.clear delegates to default instance" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("key1", result, 5.minutes)

      Fetcher::Cache.clear

      Fetcher::Cache.get("key1").should be_nil
    end

    it "Cache.stats delegates to default instance" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("test_key", result, 5.minutes)
      Fetcher::Cache.get("test_key")
      Fetcher::Cache.get("nonexistent")

      stats = Fetcher::Cache.stats
      stats.hits.should eq(1)
      stats.misses.should eq(1)
    end

    it "Cache.enabled delegates to default instance" do
      Fetcher::Cache.enabled = false
      Fetcher::Cache.enabled?.should be_false
      Fetcher::Cache.enabled = true
    end

    it "Cache.max_size delegates to default instance" do
      Fetcher::Cache.max_size = 50
      Fetcher::Cache.max_size.should eq(50)
    end

    it "Cache.generate_key delegates to Reddit" do
      key = Fetcher::Cache.generate_key("crystal", "hot", 25)
      key.should eq("reddit:crystal:hot:25")
    end

    it "Cache.ttl_for_sort delegates to Reddit" do
      Fetcher::Cache.ttl_for_sort("hot").should eq(2.minutes)
    end

    it "Cache.clear_subreddit delegates to Reddit.clear_cache" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://example.com")
      Fetcher::Cache.set("reddit:crystal:hot:25", result, 5.minutes)
      Fetcher::Cache.set("reddit:news:hot:25", result, 5.minutes)

      Fetcher::Cache.clear_subreddit("crystal")

      Fetcher::Cache.get("reddit:crystal:hot:25").should be_nil
      Fetcher::Cache.get("reddit:news:hot:25").should_not be_nil
    end
  end
end
