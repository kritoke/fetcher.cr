require "spec"
require "../src/fetcher"

describe Fetcher::Entry do
  it "creates entry with required fields" do
    entry = Fetcher::Entry.new(
      title: "Test Title",
      url: "https://example.com",
      content: "Test content",
      author: nil,
      published_at: nil,
      source_type: Fetcher::SourceType::RSS,
      version: nil
    )
    entry.title.should eq("Test Title")
    entry.url.should eq("https://example.com")
    entry.source_type.should eq(Fetcher::SourceType::RSS)
  end

  it "creates entry with all fields" do
    time = Time.utc(2024, 1, 15, 10, 30, 0)
    entry = Fetcher::Entry.new(
      title: "Test Title",
      url: "https://example.com",
      content: "Test content",
      author: "author",
      published_at: time,
      source_type: Fetcher::SourceType::Atom,
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
      source_type: Fetcher::SourceType::RSS,
      version: nil
    )
    result = Fetcher::Result.new(
      entries: [entry],
      etag: nil,
      last_modified: nil,
      site_link: "https://example.com",
      favicon: nil,
      error: nil
    )
    result.entries.size.should eq(1)
    result.site_link.should eq("https://example.com")
  end

  it "can hold error" do
    result = Fetcher::Result.new(
      entries: [] of Fetcher::Entry,
      etag: nil,
      last_modified: nil,
      site_link: nil,
      favicon: nil,
      error: Fetcher::Error.unknown("Network error")
    )
    result.error.should_not be_nil
    result.error_message.should eq("Network error")
  end

  it "can hold etag and last_modified" do
    result = Fetcher::Result.new(
      entries: [] of Fetcher::Entry,
      etag: "abc123",
      last_modified: "Wed, 15 Jan 2024 10:00:00 GMT",
      site_link: nil,
      favicon: nil,
      error: nil
    )
    result.etag.should eq("abc123")
    result.last_modified.should eq("Wed, 15 Jan 2024 10:00:00 GMT")
  end
end
