require "http/client"
require "../src/fetcher"
require "spec"

describe Fetcher::Entry do
  it "creates entry with required fields" do
    entry = Fetcher::Entry.new(
      title: "Test Title",
      url: "https://example.com",
      content: "Test content",
      author: nil,
      published_at: nil,
      source_type: "rss",
      version: nil
    )
    entry.title.should eq("Test Title")
    entry.url.should eq("https://example.com")
    entry.source_type.should eq("rss")
  end

  it "creates entry with all fields" do
    time = Time.utc(2024, 1, 15, 10, 30, 0)
    entry = Fetcher::Entry.new(
      title: "Test Title",
      url: "https://example.com",
      content: "Test content",
      author: "author",
      published_at: time,
      source_type: "rss",
      version: "1.0.0"
    )
    entry.title.should eq("Test Title")
    entry.author.should eq("author")
    entry.published_at.should eq(time)
    entry.version.should eq("1.0.0")
  end
end

describe Fetcher::Result do
  it "creates result with entries" do
    entry = Fetcher::Entry.new(
      title: "Test",
      url: "https://example.com",
      content: "",
      author: nil,
      published_at: nil,
      source_type: "rss",
      version: nil
    )
    result = Fetcher::Result.new(
      entries: [entry],
      etag: nil,
      last_modified: nil,
      site_link: "https://example.com",
      favicon: nil,
      error_message: nil
    )
    result.entries.size.should eq(1)
    result.site_link.should eq("https://example.com")
  end

  it "can hold error message" do
    result = Fetcher::Result.new(
      entries: [] of Fetcher::Entry,
      etag: nil,
      last_modified: nil,
      site_link: nil,
      favicon: nil,
      error_message: "Network error"
    )
    result.error_message.should eq("Network error")
  end

  it "can hold etag and last_modified" do
    result = Fetcher::Result.new(
      entries: [] of Fetcher::Entry,
      etag: "abc123",
      last_modified: "Wed, 15 Jan 2024 10:00:00 GMT",
      site_link: nil,
      favicon: nil,
      error_message: nil
    )
    result.etag.should eq("abc123")
    result.last_modified.should eq("Wed, 15 Jan 2024 10:00:00 GMT")
  end
end

describe Fetcher::RetryConfig do
  it "has default values" do
    config = Fetcher::RetryConfig.new
    config.max_retries.should eq(3)
    config.base_delay.should eq(1.second)
    config.max_delay.should eq(30.seconds)
    config.exponential_base.should eq(2.0)
  end

  it "calculates delay for attempts" do
    config = Fetcher::RetryConfig.new
    config.delay_for_attempt(0).should eq(1.second)
    config.delay_for_attempt(1).should eq(2.seconds)
    config.delay_for_attempt(2).should eq(4.seconds)
  end

  it "caps delay at max_delay" do
    config = Fetcher::RetryConfig.new(base_delay: 10.seconds, max_delay: 30.seconds)
    config.delay_for_attempt(1).should eq(20.seconds)
    config.delay_for_attempt(2).should eq(30.seconds)
    config.delay_for_attempt(10).should eq(30.seconds)
  end
end

describe Fetcher::DriverType do
  it "has all expected values" do
    Fetcher::DriverType.values.should contain(Fetcher::DriverType::RSS)
    Fetcher::DriverType.values.should contain(Fetcher::DriverType::Reddit)
    Fetcher::DriverType.values.should contain(Fetcher::DriverType::Software)
  end
end

describe Fetcher do
  describe ".error_result" do
    it "creates error result with message" do
      result = Fetcher.error_result("Something went wrong")
      result.error_message.should eq("Something went wrong")
      result.entries.should be_empty
      result.etag.should be_nil
      result.last_modified.should be_nil
    end
  end

  describe ".transient_error?" do
    it "detects timeout errors" do
      ex = Exception.new("Connection timeout")
      Fetcher.transient_error?(ex).should be_true
    end

    it "detects connection errors" do
      ex = Exception.new("Failed to establish connection")
      Fetcher.transient_error?(ex).should be_true
    end

    it "detects DNS errors" do
      ex = Exception.new("DNS resolution failed")
      Fetcher.transient_error?(ex).should be_true
    end

    it "does not detect other errors" do
      ex = Exception.new("Invalid format")
      Fetcher.transient_error?(ex).should be_false
    end
  end

  describe ".detect_driver" do
    it "detects Reddit driver" do
      Fetcher.detect_driver("https://reddit.com/r/crystal").should eq(Fetcher::DriverType::Reddit)
      Fetcher.detect_driver("https://www.reddit.com/r/crystal/hot").should eq(Fetcher::DriverType::Reddit)
    end

    it "detects GitHub releases" do
      Fetcher.detect_driver("https://github.com/crystal-lang/crystal/releases").should eq(Fetcher::DriverType::Software)
      Fetcher.detect_driver("https://github.com/crystal-lang/crystal/releases/tag/v1.0.0").should eq(Fetcher::DriverType::Software)
    end

    it "detects GitLab releases" do
      Fetcher.detect_driver("https://gitlab.com/foo/bar/-/releases").should eq(Fetcher::DriverType::Software)
    end

    it "detects Codeberg releases" do
      Fetcher.detect_driver("https://codeberg.org/foo/bar/releases").should eq(Fetcher::DriverType::Software)
    end

    it "defaults to RSS for other URLs" do
      Fetcher.detect_driver("https://example.com/feed.xml").should eq(Fetcher::DriverType::RSS)
      Fetcher.detect_driver("https://example.com/blog/rss").should eq(Fetcher::DriverType::RSS)
      Fetcher.detect_driver("https://feeds.feedburner.com/example").should eq(Fetcher::DriverType::RSS)
    end

    it "does not detect GitHub without releases path" do
      Fetcher.detect_driver("https://github.com/crystal-lang/crystal").should eq(Fetcher::DriverType::RSS)
    end

    it "does not detect fake domains" do
      Fetcher.detect_driver("https://notreddit.com/r/test").should eq(Fetcher::DriverType::RSS)
      Fetcher.detect_driver("https://fakegithub.com/foo/releases").should eq(Fetcher::DriverType::RSS)
      Fetcher.detect_driver("https://gitlab.fake.com/foo/bar/-/releases").should eq(Fetcher::DriverType::RSS)
      Fetcher.detect_driver("https://codeberg.fake.org/foo/bar/releases").should eq(Fetcher::DriverType::RSS)
    end
  end

  describe ".pull" do
    it "auto-detects and returns error for invalid URL" do
      result = Fetcher.pull("http://invalid.invalid.test/feed.xml")
      result.error_message.should_not be_nil
    end

    it "accepts custom headers" do
      headers = HTTP::Headers{"X-Custom" => "value"}
      result = Fetcher.pull("http://invalid.invalid.test/feed.xml", headers)
      result.error_message.should_not be_nil
    end

    it "accepts etag and last_modified parameters" do
      result = Fetcher.pull(
        "http://invalid.invalid.test/feed.xml",
        HTTP::Headers.new,
        etag: "abc123",
        last_modified: "Wed, 01 Jan 2025 00:00:00 GMT"
      )
      result.error_message.should_not be_nil
    end
  end

  describe ".pull_rss" do
    it "returns error for invalid URL" do
      result = Fetcher.pull_rss("http://invalid.invalid.test/feed.xml")
      result.error_message.should_not be_nil
    end
  end

  describe ".pull_reddit" do
    it "returns error for non-reddit URL" do
      result = Fetcher.pull_reddit("https://example.com/feed.xml")
      result.error_message.should eq("Not a Reddit subreddit URL")
    end

    it "returns error for invalid subreddit" do
      result = Fetcher.pull_reddit("https://reddit.com/r/invalid_subreddit_that_does_not_exist_12345")
      result.error_message.should_not be_nil
    end
  end

  describe ".pull_software" do
    it "returns error for non-software URL" do
      result = Fetcher.pull_software("https://example.com/feed.xml")
      result.error_message.should eq("Unknown software provider")
    end

    it "returns error for invalid GitHub URL (no releases path)" do
      result = Fetcher.pull_software("https://github.com/invalid/repo")
      result.error_message.should eq("Unknown software provider")
    end
  end
end

describe Fetcher::RetriableError do
  it "creates with message" do
    ex = Fetcher::RetriableError.new("Temporary failure")
    ex.message.should eq("Temporary failure")
  end
end

describe Fetcher::Reddit::RedditFetchError do
  it "creates with message" do
    ex = Fetcher::Reddit::RedditFetchError.new("Subreddit not found")
    ex.message.should eq("Subreddit not found")
  end
end
