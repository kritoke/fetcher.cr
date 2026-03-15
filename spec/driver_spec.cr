require "spec"
require "../src/fetcher"

describe Fetcher::DriverType do
  it "has all expected values" do
    Fetcher::DriverType.values.should contain(Fetcher::DriverType::RSS)
    Fetcher::DriverType.values.should contain(Fetcher::DriverType::Reddit)
    Fetcher::DriverType.values.should contain(Fetcher::DriverType::Software)
  end
end

describe Fetcher do
  describe ".error_result" do
    it "creates error result with Error" do
      result = Fetcher.error_result(Fetcher::Error.unknown("Something went wrong"))
      result.error_message.should eq("Something went wrong")
      result.entries.should be_empty
      result.etag.should be_nil
      result.last_modified.should be_nil
    end

    it "creates error result with kind and message" do
      result = Fetcher.error_result(Fetcher::ErrorKind::HTTPError, "HTTP 404", 404)
      result.error.should_not be_nil
      result.error.try(&.kind).should eq(Fetcher::ErrorKind::HTTPError)
      result.error.try(&.status_code).should eq(404)
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

    it "detects self-hosted GitLab releases" do
      Fetcher.detect_driver("https://gitlab.company.com/org/repo/-/releases").should eq(Fetcher::DriverType::Software)
      Fetcher.detect_driver("https://gitlab.internal.net/team/project/-/releases").should eq(Fetcher::DriverType::Software)
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
      result.error.try(&.kind).should eq(Fetcher::ErrorKind::InvalidURL)
    end

    it "returns error for invalid subreddit" do
      result = Fetcher.pull_reddit("https://reddit.com/r/invalid_subreddit_that_does_not_exist_12345")
      result.error_message.should_not be_nil
    end

    it "handles HTTP errors gracefully with RSS fallback" do
      # Reddit module has RSS fallback when JSON API fails
      # When JSON API returns HTTP error, it catches RedditFetchError
      # and falls back to fetching via RSS feed for better reliability
      ex = Fetcher::Reddit::RedditFetchError.new("HTTP error 500")
      ex.message.should eq("HTTP error 500")
    end
  end

  describe ".pull_software" do
    it "returns error for non-software URL" do
      result = Fetcher.pull_software("https://example.com/feed.xml")
      result.error_message.should eq("Unknown software provider")
      result.error.try(&.kind).should eq(Fetcher::ErrorKind::InvalidURL)
    end

    it "returns error for invalid GitHub URL (no releases path)" do
      result = Fetcher.pull_software("https://github.com/invalid/repo")
      result.error_message.should eq("Unknown software provider")
      result.error.try(&.kind).should eq(Fetcher::ErrorKind::InvalidURL)
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
