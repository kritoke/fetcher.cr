require "spec"
require "../../src/fetcher"

describe "Integration Tests - Full Fetch Flow" do
  describe "RSS feed fetching" do
    it "fetches a real RSS feed" do
      result = Fetcher.pull("http://feeds.bbci.co.uk/news/world/rss.xml", limit: 5)

      result.success?.should be_true
      result.entries.size.should be > 0
    end

    it "handles RSS feed with streaming parser" do
      config = Fetcher::RequestConfig.new(streaming: Fetcher::StreamingConfig.new(enabled: true))
      result = Fetcher.pull("http://feeds.bbci.co.uk/news/world/rss.xml", limit: 5, config: config)

      result.success?.should be_true
    end

    it "handles RSS feed with streaming parser" do
      config = Fetcher::RequestConfig.new(streaming: Fetcher::StreamingConfig.new(enabled: true))
      result = Fetcher.pull("https://httpbin.org/xml", limit: 5, config: config)

      result.success?.should be_true
    end

    it "returns error for invalid URL" do
      result = Fetcher.pull("https://invalid-domain-that-does-not-exist-12345.com/feed.xml")

      result.success?.should be_false
    end
  end

  describe "JSON Feed fetching" do
    it "fetches JSON Feed format" do
      result = Fetcher.pull("https://httpbin.org/json", limit: 5)

      result.success?.should be_true
    end
  end

  describe "Software releases fetching" do
    it "fetches GitHub releases" do
      result = Fetcher.pull("https://github.com/crystal-lang/crystal/releases", limit: 3)

      result.success?.should be_true
      result.entries.size.should be > 0
    end

    it "extracts version from release tag" do
      result = Fetcher.pull("https://github.com/crystal-lang/crystal/releases", limit: 1)

      result.success?.should be_true
      if result.entries.size > 0
        entry = result.entries[0]
        entry.version.should_not be_nil
      end
    end
  end

  describe "Error handling" do
    it "handles DNS errors gracefully" do
      result = Fetcher.pull("https://this-domain-does-not-exist-xyz123.com/feed.xml")

      result.success?.should be_false
      result.error.should_not be_nil
    end

    it "handles 404 responses" do
      result = Fetcher.pull("https://httpbin.org/status/404")

      result.success?.should be_false
    end

    it "handles 500 server errors" do
      result = Fetcher.pull("https://httpbin.org/status/500")

      result.success?.should be_false
    end
  end

  describe "Cache integration" do
    it "caches results when enabled" do
      url = "https://httpbin.org/xml"
      config = Fetcher::RequestConfig.new(cache_config: Fetcher::CacheConfig.new(enabled: true, max_size: 100))

      result1 = Fetcher.pull(url, config: config)
      result2 = Fetcher.pull(url, config: config)

      result1.success?.should be_true
      result2.success?.should be_true
    end

    it "skips cache when disabled" do
      url = "https://httpbin.org/xml"
      config = Fetcher::RequestConfig.new(cache_config: Fetcher::CacheConfig.new(enabled: false))

      result = Fetcher.pull(url, config: config)
      result.success?.should be_true
    end
  end

  describe "Retry mechanism" do
    it "respects max_retries configuration" do
      config = Fetcher::RequestConfig.new(retry: Fetcher::RetryConfig.new(max_retries: 0))

      result = Fetcher.pull("https://invalid-domain-that-does-not-exist-12345.com/feed.xml", config: config)

      result.success?.should be_false
    end
  end

  describe "URL validation and SSRF protection" do
    it "rejects invalid URLs" do
      result = Fetcher.pull("not-a-valid-url")
      result.success?.should be_false
    end

    it "rejects URLs with private IP addresses" do
      result = Fetcher.pull("http://127.0.0.1/admin/secret.xml")
      result.success?.should be_false
    end

    it "rejects localhost URLs" do
      result = Fetcher.pull("http://localhost/admin/secret.xml")
      result.success?.should be_false
    end

    it "rejects URLs with private hostnames" do
      result = Fetcher.pull("http://internal.corp/admin/secret.xml")
      result.success?.should be_false
    end
  end

  describe "Redirect handling" do
    it "follows redirects with validation" do
      result = Fetcher.pull("https://httpbin.org/redirect-to?url=https://httpbin.org/xml", limit: 5)

      result.success?.should be_true
    end
  end
end
