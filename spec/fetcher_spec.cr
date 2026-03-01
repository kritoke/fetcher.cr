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

describe Fetcher::TimeParser do
  it "parses RSS date formats" do
    time = Fetcher::TimeParser.parse("Wed, 15 Jan 2024 10:30:00 +0000")
    time.should_not be_nil
    time.try(&.year).should eq(2024)
    time.try(&.month).should eq(1)
    time.try(&.day).should eq(15)
  end

  it "parses ISO8601 date formats" do
    time = Fetcher::TimeParser.parse("2024-01-15T10:30:00Z")
    time.should_not be_nil
    time.try(&.year).should eq(2024)
    time.try(&.month).should eq(1)
    time.try(&.day).should eq(15)
  end

  it "returns nil for invalid dates" do
    time = Fetcher::TimeParser.parse("invalid date")
    time.should be_nil
  end

  it "returns nil for empty strings" do
    time = Fetcher::TimeParser.parse("")
    time.should be_nil
  end

  it "parses GitHub ISO8601 format" do
    time = Fetcher::TimeParser.parse_iso8601("2024-01-15T10:30:00Z")
    time.should_not be_nil
    time.try(&.year).should eq(2024)
  end
end

describe "Integration Tests" do
  describe "RSS parsing" do
    it "parses valid RSS feed structure" do
      rss_xml = <<-XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <link>https://example.com</link>
          <item>
            <title>Test Article</title>
            <link>https://example.com/article</link>
            <pubDate>Wed, 15 Jan 2024 10:30:00 +0000</pubDate>
          </item>
        </channel>
      </rss>
      XML

      xml = XML.parse(rss_xml)
      channel = xml.xpath_node("//channel")
      channel.should_not be_nil
      channel.try(&.xpath_node("title").try(&.text)).should eq("Test Feed")
    end

    it "parses valid Atom feed structure" do
      atom_xml = <<-XML
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test Atom Feed</title>
        <link rel="alternate" href="https://example.com"/>
        <entry>
          <title>Test Entry</title>
          <link href="https://example.com/entry"/>
          <published>2024-01-15T10:30:00Z</published>
        </entry>
      </feed>
      XML

      xml = XML.parse(atom_xml)
      feed = xml.xpath_node("//*[local-name()='feed']")
      feed.should_not be_nil
      feed.try(&.xpath_node("//*[local-name()='title']").try(&.text)).should eq("Test Atom Feed")
    end
  end

  describe "Reddit JSON parsing" do
    it "parses valid Reddit JSON structure" do
      reddit_json = <<-JSON
      [
        {
          "kind": "Listing",
          "data": {
            "children": [
              {
                "kind": "t3",
                "data": {
                  "title": "Test Post",
                  "url": "https://example.com",
                  "permalink": "/r/crystal/comments/test/",
                  "created_utc": 1705315800.0,
                  "is_self": false
                }
              }
            ]
          }
        }
      ]
      JSON

      parsed = JSON.parse(reddit_json)
      children = parsed[0]["data"]["children"]
      children.should_not be_nil
      children.as_a.size.should eq(1)

      post = children[0]["data"]
      post["title"].as_s.should eq("Test Post")
      post["created_utc"].as_f.should eq(1705315800.0)
    end
  end

  describe "GitHub releases JSON parsing" do
    it "parses valid GitHub releases structure" do
      github_json = <<-JSON
      [
        {
          "tag_name": "v1.0.0",
          "name": "Release 1.0.0",
          "html_url": "https://github.com/test/repo/releases/v1.0.0",
          "published_at": "2024-01-15T10:30:00Z",
          "prerelease": false,
          "draft": false
        }
      ]
      JSON

      releases = Array(JSON::Any).from_json(github_json)
      releases.size.should eq(1)

      release = releases[0]
      release["tag_name"].as_s.should eq("v1.0.0")
      release["prerelease"].as_bool.should be_false
    end

    it "filters out prereleases" do
      github_json = <<-JSON
      [
        {
          "tag_name": "v1.0.0",
          "name": "Stable",
          "prerelease": false,
          "draft": false
        },
        {
          "tag_name": "v1.1.0-beta",
          "name": "Beta",
          "prerelease": true,
          "draft": false
        }
      ]
      JSON

      releases = Array(JSON::Any).from_json(github_json)
      stable = releases.reject { |release| release["prerelease"]?.try(&.as_bool) || release["draft"]?.try(&.as_bool) }
      stable.size.should eq(1)
      stable[0]["tag_name"].as_s.should eq("v1.0.0")
    end
  end
end

describe "Phase 1: Content Extraction" do
  describe "RSS content extraction" do
    it "extracts content:encoded over description" do
      xml = <<-XML
      <?xml version="1.0"?>
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel>
          <title>Test</title>
          <item>
            <title>Test</title>
            <description>Excerpt</description>
            <content:encoded><![CDATA[<p>Full content</p>]]></content:encoded>
          </item>
        </channel>
      </rss>
      XML

      parsed = XML.parse(xml)
      item = parsed.xpath_node("//item")
      content_encoded = item.try(&.xpath_node(".//*[local-name()='encoded']").try(&.text))
      description = item.try(&.xpath_node(".//*[local-name()='description']").try(&.text))
      content = content_encoded || description || ""

      content.should eq("<p>Full content</p>")
    end

    it "extracts dc:creator as author" do
      xml = <<-XML
      <?xml version="1.0"?>
      <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <channel>
          <title>Test</title>
          <item>
            <title>Test</title>
            <dc:creator>John Doe</dc:creator>
          </item>
        </channel>
      </rss>
      XML

      parsed = XML.parse(xml)
      item = parsed.xpath_node("//item")
      dc_creator = item.try(&.xpath_node(".//*[local-name()='creator']").try(&.text))
      author = dc_creator.try(&.strip).presence

      author.should eq("John Doe")
    end

    it "extracts categories" do
      xml = <<-XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Test</title>
          <item>
            <title>Test</title>
            <category>Technology</category>
            <category>Programming</category>
          </item>
        </channel>
      </rss>
      XML

      parsed = XML.parse(xml)
      item = parsed.xpath_node("//item")
      categories = item.try(&.xpath_nodes(".//*[local-name()='category']").compact_map(&.text.try(&.strip).presence)) || [] of String

      categories.size.should eq(2)
      categories.should contain("Technology")
      categories.should contain("Programming")
    end

    it "extracts enclosures as attachments" do
      xml = <<-XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Test</title>
          <item>
            <title>Test</title>
            <enclosure url="https://example.com/file.mp3" type="audio/mpeg" length="123456"/>
          </item>
        </channel>
      </rss>
      XML

      parsed = XML.parse(xml)
      item = parsed.xpath_node("//item")
      enclosures = item.try(&.xpath_nodes(".//*[local-name()='enclosure']")) || [] of XML::Node

      enclosures.size.should eq(1)
      enclosures[0]["url"].should eq("https://example.com/file.mp3")
      enclosures[0]["type"].should eq("audio/mpeg")
      enclosures[0]["length"].should eq("123456")
    end

    it "extracts feed metadata" do
      xml = <<-XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Feed Title</title>
          <link>https://example.com</link>
          <description>Feed Description</description>
          <language>en-US</language>
          <item>
            <title>Item</title>
          </item>
        </channel>
      </rss>
      XML

      parsed = XML.parse(xml)
      channel = parsed.xpath_node("//channel")
      feed_title = channel.try(&.xpath_node(".//*[local-name()='title']").try(&.text)).try(&.strip)
      feed_description = channel.try(&.xpath_node(".//*[local-name()='description']").try(&.text)).try(&.strip)
      feed_language = channel.try(&.xpath_node(".//*[local-name()='language']").try(&.text)).try(&.strip)

      feed_title.should eq("Feed Title")
      feed_description.should eq("Feed Description")
      feed_language.should eq("en-US")
    end
  end

  describe "Atom content extraction" do
    it "extracts content with HTML type" do
      xml = <<-XML
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test</title>
        <entry>
          <title>Test</title>
          <content type="html"><![CDATA[<p>HTML content</p>]]></content>
        </entry>
      </feed>
      XML

      parsed = XML.parse(xml)
      entry = parsed.xpath_node("//*[local-name()='entry']")
      content_node = entry.try(&.xpath_node(".//*[local-name()='content']"))
      content_type = content_node.try(&.[]?("type")) || "text"
      content = case content_type
                when "html", "xhtml" then content_node.try(&.text) || ""
                when "text"          then content_node.try(&.text) || ""
                else                      ""
                end

      content.should eq("<p>HTML content</p>")
    end

    it "extracts author name and uri" do
      xml = <<-XML
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test</title>
        <entry>
          <title>Test</title>
          <author>
            <name>Jane Doe</name>
            <uri>https://example.com/jane</uri>
          </author>
        </entry>
      </feed>
      XML

      parsed = XML.parse(xml)
      entry = parsed.xpath_node("//*[local-name()='entry']")
      author_node = entry.try(&.xpath_node(".//*[local-name()='author']"))
      author_name = author_node.try(&.xpath_node(".//*[local-name()='name']").try(&.text))
      author_uri = author_node.try(&.xpath_node(".//*[local-name()='uri']").try(&.text))

      author_name.should eq("Jane Doe")
      author_uri.should eq("https://example.com/jane")
    end

    it "extracts categories from term attribute" do
      xml = <<-XML
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test</title>
        <entry>
          <title>Test</title>
          <category term="Crystal"/>
          <category term="Programming"/>
        </entry>
      </feed>
      XML

      parsed = XML.parse(xml)
      entry = parsed.xpath_node("//*[local-name()='entry']")
      categories = entry.try(&.xpath_nodes(".//*[local-name()='category']").compact_map(&.["term"]?.try(&.strip).presence)) || [] of String

      categories.size.should eq(2)
      categories.should contain("Crystal")
      categories.should contain("Programming")
    end

    it "extracts feed-level author" do
      xml = <<-XML
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test Feed</title>
        <subtitle>Feed subtitle</subtitle>
        <author>
          <name>Feed Author</name>
          <uri>https://example.com/author</uri>
        </author>
        <entry>
          <title>Entry</title>
        </entry>
      </feed>
      XML

      parsed = XML.parse(xml)
      feed = parsed.xpath_node("//*[local-name()='feed']")
      feed_title = feed.try(&.xpath_node(".//*[local-name()='title']").try(&.text))
      feed_subtitle = feed.try(&.xpath_node(".//*[local-name()='subtitle']").try(&.text))

      feed_title.should eq("Test Feed")
      feed_subtitle.should eq("Feed subtitle")
    end

    it "handles entry with summary only (no content)" do
      xml = <<-XML
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test</title>
        <entry>
          <title>Test</title>
          <summary>Just a summary</summary>
        </entry>
      </feed>
      XML

      parsed = XML.parse(xml)
      entry = parsed.xpath_node("//*[local-name()='entry']")
      content_node = entry.try(&.xpath_node(".//*[local-name()='content']"))
      summary_node = entry.try(&.xpath_node(".//*[local-name()='summary']"))
      content = content_node.try(&.text) || summary_node.try(&.text) || ""

      content.should eq("Just a summary")
    end
  end

  describe "Entry record with new fields" do
    it "creates entry with content" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: "rss",
        content: "Full content here"
      )
      entry.content.should eq("Full content here")
    end

    it "creates entry with author and author_url" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: "atom",
        author: "John Doe",
        author_url: "https://example.com/john"
      )
      entry.author.should eq("John Doe")
      entry.author_url.should eq("https://example.com/john")
    end

    it "creates entry with categories" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: "rss",
        categories: ["Ruby", "Crystal"]
      )
      entry.categories.size.should eq(2)
      entry.categories.should contain("Ruby")
    end

    it "creates entry with attachments" do
      attachment = Fetcher::Attachment.new(
        url: "https://example.com/file.mp3",
        mime_type: "audio/mpeg",
        size_in_bytes: 12345_i64
      )
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: "rss",
        attachments: [attachment]
      )
      entry.attachments.size.should eq(1)
      entry.attachments[0].mime_type.should eq("audio/mpeg")
    end
  end

  describe "Result record with feed metadata" do
    it "creates result with feed metadata" do
      author = Fetcher::Author.new(name: "Author Name", url: "https://example.com", avatar: nil)
      result = Fetcher::Result.success(
        entries: [] of Fetcher::Entry,
        feed_title: "Feed Title",
        feed_description: "Feed Description",
        feed_language: "en",
        feed_authors: [author]
      )
      result.feed_title.should eq("Feed Title")
      result.feed_description.should eq("Feed Description")
      result.feed_language.should eq("en")
      result.feed_authors.size.should eq(1)
      result.feed_authors[0].name.should eq("Author Name")
    end

    it "creates result with empty feed metadata by default" do
      result = Fetcher::Result.success(entries: [] of Fetcher::Entry)
      result.feed_title.should be_nil
      result.feed_description.should be_nil
      result.feed_language.should be_nil
      result.feed_authors.should be_empty
    end
  end
end

describe "Phase 2: JSON Feed Support" do
  describe "JSON Feed detection" do
    it "detects .json URLs as JSONFeed" do
      Fetcher.detect_driver("https://example.com/feed.json").should eq(Fetcher::DriverType::JSONFeed)
    end

    it "detects /feed.json paths as JSONFeed" do
      Fetcher.detect_driver("https://example.com/blog/feed.json").should eq(Fetcher::DriverType::JSONFeed)
    end

    it "detects /feeds/json paths as JSONFeed" do
      Fetcher.detect_driver("https://example.com/feeds/json").should eq(Fetcher::DriverType::JSONFeed)
    end

    it "does not detect .json without feed pattern as JSONFeed when it's a software URL" do
      Fetcher.detect_driver("https://github.com/user/repo/releases.json").should eq(Fetcher::DriverType::Software)
    end
  end

  describe "JSON Feed parsing" do
    it "parses valid JSON Feed structure" do
      json = <<-JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Test Feed",
        "home_page_url": "https://example.com",
        "items": [
          {
            "id": "1",
            "title": "Test Item",
            "url": "https://example.com/item-1",
            "content_text": "Test content"
          }
        ]
      }
      JSON

      parsed = JSON.parse(json)
      version = parsed["version"]?.try(&.as_s)
      title = parsed["title"]?.try(&.as_s)
      items = parsed["items"]?.try(&.as_a)

      version.should eq("https://jsonfeed.org/version/1.1")
      title.should eq("Test Feed")
      items.try(&.size).should eq(1)
    end

    it "extracts content_html over content_text" do
      json = <<-JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Test",
        "items": [{
          "id": "1",
          "content_html": "<p>HTML content</p>",
          "content_text": "Text content"
        }]
      }
      JSON

      parsed = JSON.parse(json)
      item = parsed["items"][0]
      content_html = item["content_html"]?.try(&.as_s)
      content_text = item["content_text"]?.try(&.as_s)
      content = content_html || content_text || ""

      content.should eq("<p>HTML content</p>")
    end

    it "extracts authors from item" do
      json = <<-JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Test",
        "items": [{
          "id": "1",
          "content_text": "Test",
          "authors": [{"name": "Jane Doe", "url": "https://example.com/jane"}]
        }]
      }
      JSON

      parsed = JSON.parse(json)
      item = parsed["items"][0]
      authors = item["authors"]?.try(&.as_a)
      author_name = authors.try(&.first?).try(&.["name"]?.try(&.as_s))

      author_name.should eq("Jane Doe")
    end

    it "extracts tags as categories" do
      json = <<-JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Test",
        "items": [{
          "id": "1",
          "content_text": "Test",
          "tags": ["Ruby", "Crystal"]
        }]
      }
      JSON

      parsed = JSON.parse(json)
      item = parsed["items"][0]
      tags = item["tags"]?.try(&.as_a).try(&.map(&.as_s)) || [] of String

      tags.size.should eq(2)
      tags.should contain("Ruby")
      tags.should contain("Crystal")
    end

    it "extracts attachments" do
      json = <<-JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Test",
        "items": [{
          "id": "1",
          "content_text": "Test",
          "attachments": [{
            "url": "https://example.com/file.mp3",
            "mime_type": "audio/mpeg",
            "size_in_bytes": 12345,
            "duration_in_seconds": 3600
          }]
        }]
      }
      JSON

      parsed = JSON.parse(json)
      item = parsed["items"][0]
      attachments = item["attachments"]?.try(&.as_a)

      attachments.try(&.size).should eq(1)
      att = attachments.try(&.first?)
      att.try(&.["url"].as_s).should eq("https://example.com/file.mp3")
      att.try(&.["mime_type"].as_s).should eq("audio/mpeg")
    end

    it "extracts feed-level metadata" do
      json = <<-JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Feed Title",
        "home_page_url": "https://example.com",
        "description": "Feed Description",
        "language": "en-US",
        "icon": "https://example.com/icon.png",
        "favicon": "https://example.com/favicon.ico",
        "items": []
      }
      JSON

      parsed = JSON.parse(json)
      title = parsed["title"]?.try(&.as_s)
      home_url = parsed["home_page_url"]?.try(&.as_s)
      description = parsed["description"]?.try(&.as_s)
      language = parsed["language"]?.try(&.as_s)
      favicon = parsed["favicon"]?.try(&.as_s)
      icon = parsed["icon"]?.try(&.as_s)

      title.should eq("Feed Title")
      home_url.should eq("https://example.com")
      description.should eq("Feed Description")
      language.should eq("en-US")
      favicon.should eq("https://example.com/favicon.ico")
      icon.should eq("https://example.com/icon.png")
    end

    it "extracts feed-level authors" do
      json = <<-JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Test",
        "authors": [
          {"name": "Feed Author", "url": "https://example.com/author", "avatar": "https://example.com/avatar.jpg"}
        ],
        "items": []
      }
      JSON

      parsed = JSON.parse(json)
      authors = parsed["authors"]?.try(&.as_a)
      author_name = authors.try(&.first?).try(&.["name"]?.try(&.as_s))
      author_url = authors.try(&.first?).try(&.["url"]?.try(&.as_s))
      author_avatar = authors.try(&.first?).try(&.["avatar"]?.try(&.as_s))

      author_name.should eq("Feed Author")
      author_url.should eq("https://example.com/author")
      author_avatar.should eq("https://example.com/avatar.jpg")
    end

    it "requires id field and returns nil for items without id" do
      json = <<-JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Test",
        "items": [
          {"id": "1", "content_text": "Has ID"},
          {"content_text": "No ID"}
        ]
      }
      JSON

      parsed = JSON.parse(json)
      items = parsed["items"]?.try(&.as_a) || [] of JSON::Any

      first_id = items[0]["id"]?.try(&.to_s)
      second_id = items[1]["id"]?.try(&.to_s)

      first_id.should eq("1")
      second_id.should be_nil
    end

    it "uses date_modified when date_published is missing" do
      json = <<-JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Test",
        "items": [{
          "id": "1",
          "content_text": "Test",
          "date_modified": "2024-01-17T14:00:00Z"
        }]
      }
      JSON

      parsed = JSON.parse(json)
      item = parsed["items"][0]
      published = item["date_published"]?.try(&.as_s)
      modified = item["date_modified"]?.try(&.as_s)
      date_to_parse = published || modified

      date_to_parse.should eq("2024-01-17T14:00:00Z")
    end

    it "handles feed without authors gracefully" do
      json = <<-JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Test",
        "items": [{"id": "1", "content_text": "Test"}]
      }
      JSON

      parsed = JSON.parse(json)
      authors = parsed["authors"]?.try(&.as_a) || parsed["author"]?.try(&.as_a)

      authors.should be_nil
    end
  end

  describe "Entry and Result with JSON Feed data" do
    it "creates entry from JSON Feed item" do
      attachment = Fetcher::Attachment.new(
        url: "https://example.com/file.mp3",
        mime_type: "audio/mpeg",
        size_in_bytes: 12345_i64
      )
      entry = Fetcher::Entry.create(
        title: "Test Post",
        url: "https://example.com/post",
        source_type: "jsonfeed",
        content: "<p>HTML content</p>",
        author: "John Doe",
        author_url: "https://example.com/john",
        categories: ["Tech", "News"],
        attachments: [attachment]
      )

      entry.title.should eq("Test Post")
      entry.source_type.should eq("jsonfeed")
      entry.content.should eq("<p>HTML content</p>")
      entry.author.should eq("John Doe")
      entry.author_url.should eq("https://example.com/john")
      entry.categories.size.should eq(2)
      entry.attachments.size.should eq(1)
    end

    it "creates result with JSON Feed metadata" do
      author = Fetcher::Author.new(
        name: "Feed Author",
        url: "https://example.com/author",
        avatar: "https://example.com/avatar.jpg"
      )
      result = Fetcher::Result.success(
        entries: [] of Fetcher::Entry,
        feed_title: "JSON Feed Title",
        feed_description: "JSON Feed Description",
        feed_language: "en",
        feed_authors: [author],
        favicon: "https://example.com/favicon.ico"
      )

      result.feed_title.should eq("JSON Feed Title")
      result.feed_description.should eq("JSON Feed Description")
      result.feed_language.should eq("en")
      result.feed_authors.size.should eq(1)
      result.feed_authors[0].name.should eq("Feed Author")
      result.favicon.should eq("https://example.com/favicon.ico")
    end
  end
end

describe "Phase 4: HTTP Improvements" do
  describe "RequestConfig" do
    it "has default values" do
      config = Fetcher::RequestConfig.new
      config.connect_timeout.should eq(10.seconds)
      config.read_timeout.should eq(30.seconds)
      config.max_redirects.should eq(5)
      config.follow_redirects.should be_true
      config.ssl_verify.should be_true
    end

    it "accepts custom timeouts" do
      config = Fetcher::RequestConfig.new(
        connect_timeout: 30.seconds,
        read_timeout: 60.seconds
      )
      config.connect_timeout.should eq(30.seconds)
      config.read_timeout.should eq(60.seconds)
    end

    it "can disable redirects" do
      config = Fetcher::RequestConfig.new(follow_redirects: false)
      config.follow_redirects.should be_false
    end
  end

  describe "Headers with compression" do
    it "includes Accept-Encoding header" do
      headers = Fetcher::Headers.build
      headers["Accept-Encoding"]?.should eq("gzip, deflate")
    end

    it "preserves custom Accept-Encoding" do
      custom = HTTP::Headers{"Accept-Encoding" => "br"}
      headers = Fetcher::Headers.build(custom)
      headers["Accept-Encoding"]?.should eq("br")
    end
  end

  describe "pull with RequestConfig" do
    it "accepts config parameter" do
      config = Fetcher::RequestConfig.new(
        connect_timeout: 5.seconds,
        read_timeout: 15.seconds
      )
      result = Fetcher.pull("http://invalid.invalid.test/feed.xml", config: config)
      result.error_message.should_not be_nil
    end

    it "uses default config when not provided" do
      result = Fetcher.pull("http://invalid.invalid.test/feed.xml")
      result.error_message.should_not be_nil
    end
  end

  describe "pull_* methods with RequestConfig" do
    it "pull_rss accepts config" do
      config = Fetcher::RequestConfig.new(read_timeout: 60.seconds)
      result = Fetcher.pull_rss("http://invalid.invalid.test/feed.xml", config: config)
      result.error_message.should_not be_nil
    end

    it "pull_reddit accepts config" do
      config = Fetcher::RequestConfig.new(connect_timeout: 20.seconds)
      result = Fetcher.pull_reddit("https://reddit.com/r/test", config: config)
      result.error_message.should_not be_nil
    end

    it "pull_software accepts config" do
      config = Fetcher::RequestConfig.new(read_timeout: 45.seconds)
      result = Fetcher.pull_software("https://github.com/user/repo/releases", config: config)
      result.error_message.should_not be_nil
    end

    it "pull_json_feed accepts config" do
      config = Fetcher::RequestConfig.new(connect_timeout: 15.seconds)
      result = Fetcher.pull_json_feed("https://example.com/feed.json", config: config)
      result.error_message.should_not be_nil
    end
  end
end

describe "Integration Tests - Fixtures" do
  describe "RSS fixture" do
    it "reads WordPress fixture file" do
      File.exists?("test/fixtures/rss_wordpress.xml").should be_true
      xml = File.read("test/fixtures/rss_wordpress.xml")
      xml.should contain("content:encoded")
      xml.should contain("dc:creator")
    end

    it "has podcast enclosure in fixture" do
      xml = File.read("test/fixtures/rss_wordpress.xml")
      xml.should contain("audio/mpeg")
    end
  end

  describe "Atom fixture" do
    it "reads Atom fixture file" do
      File.exists?("test/fixtures/atom_full.xml").should be_true
      xml = File.read("test/fixtures/atom_full.xml")
      xml.should contain("type=\"html\"")
      xml.should contain("xml:lang")
    end
  end

  describe "JSON Feed fixture" do
    it "reads JSON Feed fixture file" do
      File.exists?("test/fixtures/jsonfeed_full.json").should be_true
      json = File.read("test/fixtures/jsonfeed_full.json")
      json.should contain("content_html")
      json.should contain("attachments")
    end

    it "parses JSON Feed fixture" do
      json = File.read("test/fixtures/jsonfeed_full.json")
      parsed = JSON.parse(json)

      parsed["version"].as_s.should eq("https://jsonfeed.org/version/1.1")
      parsed["title"].as_s.should eq("Test JSON Feed")
      parsed["items"].as_a.size.should eq(3)
    end

    it "extracts attachments from JSON Feed fixture" do
      json = File.read("test/fixtures/jsonfeed_full.json")
      parsed = JSON.parse(json)
      item = parsed["items"][0]
      attachments = item["attachments"].as_a

      attachments.size.should eq(1)
      attachments[0]["mime_type"].as_s.should eq("audio/mpeg")
      attachments[0]["duration_in_seconds"].as_i.should eq(3600)
    end
  end

  describe "HTTP compression" do
    it "includes Accept-Encoding header" do
      headers = Fetcher::Headers.build
      headers["Accept-Encoding"].should eq("gzip, deflate")
    end
  end

  describe "RequestConfig" do
    it "has configurable timeouts" do
      config = Fetcher::RequestConfig.new(
        connect_timeout: 30.seconds,
        read_timeout: 60.seconds
      )
      config.connect_timeout.should eq(30.seconds)
      config.read_timeout.should eq(60.seconds)
    end

    it "has default values" do
      config = Fetcher::RequestConfig.new
      config.max_redirects.should eq(5)
      config.follow_redirects.should be_true
    end
  end
end
