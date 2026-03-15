require "http/client"
require "../src/fetcher"

# Integration test helper for real feed fetching
module IntegrationTestHelper
  # Test with actual RSS feed
  def self.test_rss_feed
    url = "https://feeds.feedburner.com/oreilly/radar"
    result = Fetcher.pull(url)
    result.success?.should be_true
    result.entries.size.should be > 0
    result.entries[0].title.should_not be_nil
    result.entries[0].url.should_not be_nil
  end

  # Test with actual Atom feed
  def self.test_atom_feed
    url = "https://www.w3.org/News/atom.xml"
    result = Fetcher.pull(url)
    result.success?.should be_true
    result.entries.size.should be > 0
    result.entries[0].title.should_not be_nil
    result.entries[0].url.should_not be_nil
  end

  # Test with JSON Feed (if available)
  def self.test_json_feed
    # Using a known JSON Feed
    url = "https://davegandy.com/feed.json"
    result = Fetcher.pull(url)
    result.success?.should be_true
    result.entries.size.should be > 0
    result.entries[0].title.should_not be_nil
    result.entries[0].url.should_not be_nil
  end

  # Test with Reddit
  def self.test_reddit_feed
    url = "https://reddit.com/r/crystal"
    result = Fetcher.pull(url)
    result.success?.should be_true
    result.entries.size.should be > 0
    result.entries[0].title.should_not be_nil
    result.entries[0].url.should_not be_nil
  end

  # Test with GitHub releases
  def self.test_github_releases
    url = "https://github.com/crystal-lang/crystal/releases"
    result = Fetcher.pull(url)
    result.success?.should be_true
    result.entries.size.should be > 0
    result.entries[0].title.should_not be_nil
    result.entries[0].url.should_not be_nil
  end
end
