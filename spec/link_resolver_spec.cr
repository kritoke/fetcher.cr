require "spec"
require "../src/fetcher"
require "xml"

describe Fetcher::LinkResolver do
  describe "detect_discussion_url" do
    it "detects /comments/ in URL" do
      result = Fetcher::LinkResolver.resolve_from_url("https://www.reddit.com/r/crystal/comments/abc123")
      result.is_discussion_url.should be_true
    end

    it "detects /item?id= for Hacker News" do
      result = Fetcher::LinkResolver.resolve_from_url("https://news.ycombinator.com/item?id=12345")
      result.is_discussion_url.should be_true
    end

    it "detects /s/ for Lobste.rs" do
      result = Fetcher::LinkResolver.resolve_from_url("https://lobste.rs/s/abc123")
      result.is_discussion_url.should be_true
    end

    it "detects /discuss/ in URL" do
      result = Fetcher::LinkResolver.resolve_from_url("https://example.com/discuss/123")
      result.is_discussion_url.should be_true
    end

    it "detects /r/ for Reddit" do
      result = Fetcher::LinkResolver.resolve_from_url("https://www.reddit.com/r/technology")
      result.is_discussion_url.should be_true
    end

    it "returns false for regular article URLs" do
      result = Fetcher::LinkResolver.resolve_from_url("https://example.com/article/123")
      result.is_discussion_url.should be_false
    end

    it "returns false for empty URL" do
      result = Fetcher::LinkResolver.resolve_from_url("")
      result.is_discussion_url.should be_false
    end

    it "returns false for # URL" do
      result = Fetcher::LinkResolver.resolve_from_url("#")
      result.is_discussion_url.should be_false
    end
  end

  describe "resolve from XML node" do
    it "extracts comment_url from rel=\"replies\"" do
      xml = <<-XML
        <item>
          <title>Test</title>
          <link>https://example.com/article</link>
          <link rel="replies" href="https://news.ycombinator.com/item?id=12345"/>
        </item>
        XML

      node = XML.parse(xml).xpath_node("//item")
      result = Fetcher::LinkResolver.resolve(node.not_nil!, "https://example.com/article")
      result.comment_url.should eq("https://news.ycombinator.com/item?id=12345")
    end

    it "extracts comment_url from rel=\"comments\"" do
      xml = <<-XML
        <item>
          <title>Test</title>
          <link>https://example.com/article</link>
          <link rel="comments" href="https://example.com/comments/123"/>
        </item>
        XML

      node = XML.parse(xml).xpath_node("//item")
      result = Fetcher::LinkResolver.resolve(node.not_nil!, "https://example.com/article")
      result.comment_url.should eq("https://example.com/comments/123")
    end

    it "extracts commentary_url from rel=\"related\"" do
      xml = <<-XML
        <item>
          <title>Test</title>
          <link>https://example.com/article</link>
          <link rel="related" href="https://daringfireball.net/linked/2024/01/article"/>
        </item>
        XML

      node = XML.parse(xml).xpath_node("//item")
      result = Fetcher::LinkResolver.resolve(node.not_nil!, "https://example.com/article")
      result.commentary_url.should eq("https://daringfireball.net/linked/2024/01/article")
    end

    it "handles Daring Fireball style entry" do
      xml = <<-XML
        <entry>
          <title>Fox Sports to Broadcast...</title>
          <link rel="alternate" href="https://x.com/mlbonfox/status/123"/>
          <link rel="related" href="https://daringfireball.net/linked/2026/03/17/fox-sports-wbc-immersive"/>
        </entry>
        XML

      node = XML.parse(xml).xpath_node("//entry")
      result = Fetcher::LinkResolver.resolve(node.not_nil!, "https://x.com/mlbonfox/status/123")
      result.commentary_url.should eq("https://daringfireball.net/linked/2026/03/17/fox-sports-wbc-immersive")
      result.is_discussion_url.should be_false
    end

    it "sets is_discussion_url when main URL is discussion" do
      xml = <<-XML
        <item>
          <title>Test</title>
          <link>https://news.ycombinator.com/item?id=12345</link>
        </item>
        XML

      node = XML.parse(xml).xpath_node("//item")
      result = Fetcher::LinkResolver.resolve(node.not_nil!, "https://news.ycombinator.com/item?id=12345")
      result.is_discussion_url.should be_true
      result.comment_url.should eq("https://news.ycombinator.com/item?id=12345")
    end
  end
end

describe Fetcher::Entry do
  describe "new comment fields" do
    it "creates entry with comment_url" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        comment_url: "https://news.ycombinator.com/item?id=123"
      )
      entry.comment_url.should eq("https://news.ycombinator.com/item?id=123")
    end

    it "creates entry with commentary_url" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        commentary_url: "https://daringfireball.net/linked/2024/01/test"
      )
      entry.commentary_url.should eq("https://daringfireball.net/linked/2024/01/test")
    end

    it "creates entry with is_discussion_url" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://news.ycombinator.com/item?id=123",
        source_type: Fetcher::SourceType::RSS,
        is_discussion_url: true
      )
      entry.is_discussion_url.should be_true
    end

    it "defaults to nil/false when not provided" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS
      )
      entry.comment_url.should be_nil
      entry.commentary_url.should be_nil
      entry.is_discussion_url.should be_false
    end
  end
end
