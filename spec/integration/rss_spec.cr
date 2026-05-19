require "spec"
require "../../src/fetcher"

describe "Integration Tests - RSS" do
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
          source_type: Fetcher::SourceType::RSS,
          content: "Full content here"
        )
        entry.content.should eq("Full content here")
      end

      it "creates entry with author and author_url" do
        entry = Fetcher::Entry.create(
          title: "Test",
          url: "https://example.com",
          source_type: Fetcher::SourceType::Atom,
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
          source_type: Fetcher::SourceType::RSS,
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
          source_type: Fetcher::SourceType::RSS,
          attachments: [attachment]
        )
        entry.attachments.size.should eq(1)
        entry.attachments[0].mime_type.should eq("audio/mpeg")
      end
    end

    describe "Result record with feed metadata" do
      it "creates result with feed metadata" do
        author = Fetcher::Author.new(name: "Author Name", url: "https://example.com", avatar: nil)
        result = Fetcher::Result.builder.entries([] of Fetcher::Entry).feed_title("Feed Title").feed_description("Feed Description").feed_language("en").feed_authors([author]).build
        result.feed_title.should eq("Feed Title")
        result.feed_description.should eq("Feed Description")
        result.feed_language.should eq("en")
        result.feed_authors.size.should eq(1)
        result.feed_authors[0].name.should eq("Author Name")
      end

      it "creates result with empty feed metadata by default" do
        result = Fetcher::Result.builder.entries([] of Fetcher::Entry).build
        result.feed_title.should be_nil
        result.feed_description.should be_nil
        result.feed_language.should be_nil
        result.feed_authors.should be_empty
      end
    end

    describe "RSS 2.0 comments element extraction" do
      it "extracts comments element via DOM parser" do
        rss_xml = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Test Feed</title>
              <item>
                <title>Test Article</title>
                <link>https://example.com/article</link>
                <comments>https://example.com/article/comments</comments>
              </item>
            </channel>
          </rss>
          XML

        parser = Fetcher::RSSParser.new
        entries = parser.parse_entries(rss_xml, 10)
        entries.size.should eq(1)
        entries[0].comment_url.should eq("https://example.com/article/comments")
      end

      it "extracts comments element via streaming parser" do
        xml_with_whitespace = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Test Feed</title>
              <item>
                <title>Test Article</title>
                <link>https://example.com/article</link>
                <comments>https://example.com/article/comments</comments>
              </item>
            </channel>
          </rss>
        XML
        rss_xml = xml_with_whitespace.lstrip

        reader = XML::Reader.new(rss_xml)
        parser = Fetcher::StreamingRSSParser.new
        entries = parser.parse_entries(reader, 10)
        entries.size.should eq(1)
        entries[0].comment_url.should eq("https://example.com/article/comments")
      end

      it "comments element is used as fallback when no link rel=comments via DOM parser" do
        rss_xml = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Test Feed</title>
              <item>
                <title>Test Article</title>
                <link>https://example.com/article</link>
                <comments>https://example.com/native-comments</comments>
              </item>
            </channel>
          </rss>
          XML

        parser = Fetcher::RSSParser.new
        entries = parser.parse_entries(rss_xml, 10)
        entries.size.should eq(1)
        entries[0].comment_url.should eq("https://example.com/native-comments")
      end

      it "link rel=comments takes precedence over comments element via DOM parser" do
        rss_xml = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Test Feed</title>
              <item>
                <title>Test Article</title>
                <link>https://example.com/article</link>
                <link rel="comments" href="https://example.com/rel-comments"/>
                <comments>https://example.com/native-comments</comments>
              </item>
            </channel>
          </rss>
          XML

        parser = Fetcher::RSSParser.new
        entries = parser.parse_entries(rss_xml, 10)
        entries.size.should eq(1)
        entries[0].comment_url.should eq("https://example.com/rel-comments")
      end

      it "streaming parser uses comments element as fallback when no discussion URL" do
        xml_with_whitespace = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Test Feed</title>
              <item>
                <title>Test Article</title>
                <link>https://example.com/article</link>
                <comments>https://example.com/article/comments</comments>
              </item>
            </channel>
          </rss>
        XML
        rss_xml = xml_with_whitespace.lstrip

        reader = XML::Reader.new(rss_xml)
        parser = Fetcher::StreamingRSSParser.new
        entries = parser.parse_entries(reader, 10)
        entries.size.should eq(1)
        entries[0].is_discussion_url.should be_false
        entries[0].comment_url.should eq("https://example.com/article/comments")
      end

      it "streaming parser detects discussion URL from link" do
        xml_with_whitespace = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Test Feed</title>
              <item>
                <title>HN Post</title>
                <link>https://news.ycombinator.com/item?id=12345</link>
              </item>
            </channel>
          </rss>
        XML
        rss_xml = xml_with_whitespace.lstrip

        reader = XML::Reader.new(rss_xml)
        parser = Fetcher::StreamingRSSParser.new
        entries = parser.parse_entries(reader, 10)
        entries.size.should eq(1)
        entries[0].is_discussion_url.should be_true
        entries[0].comment_url.should eq("https://news.ycombinator.com/item?id=12345")
      end
    end

    describe "streaming parser depth tracking regression" do
      it "parses multiple items with self-closing enclosure elements" do
        xml = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Test</title>
              <item>
                <title>First</title>
                <link>https://example.com/1</link>
                <enclosure url="https://example.com/pic.jpg" type="image/jpeg" length="123"/>
              </item>
              <item>
                <title>Second</title>
                <link>https://example.com/2</link>
              </item>
              <item>
                <title>Third</title>
                <link>https://example.com/3</link>
              </item>
            </channel>
          </rss>
          XML

        reader = XML::Reader.new(xml)
        parser = Fetcher::StreamingRSSParser.new
        entries = parser.parse_entries(reader, 10)
        entries.size.should eq(3)
        entries[0].title.should eq("First")
        entries[0].attachments.size.should eq(1)
        entries[0].attachments[0].mime_type.should eq("image/jpeg")
        entries[1].title.should eq("Second")
        entries[2].title.should eq("Third")
      end

      it "parses multiple items with HTML content containing self-closing tags" do
        xml = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
            <channel>
              <title>Test</title>
              <item>
                <title>Article One</title>
                <link>https://example.com/1</link>
                <description>Hello &lt;br/&gt;World&lt;br/&gt;More text</description>
              </item>
              <item>
                <title>Article Two</title>
                <link>https://example.com/2</link>
                <description>Second description</description>
              </item>
            </channel>
          </rss>
          XML

        reader = XML::Reader.new(xml)
        parser = Fetcher::StreamingRSSParser.new
        entries = parser.parse_entries(reader, 10)
        entries.size.should eq(2)
        entries[0].title.should eq("Article One")
        entries[0].content.should contain("World")
        entries[1].title.should eq("Article Two")
        entries[1].content.should eq("Second description")
      end

      it "parses items with content:encoded containing CDATA with HTML" do
        xml = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
            <channel>
              <title>Test</title>
              <item>
                <title>First</title>
                <link>https://example.com/1</link>
                <content:encoded><![CDATA[<p>Hello</p><br/><img src="test.jpg"/><p>World</p>]]></content:encoded>
              </item>
              <item>
                <title>Second</title>
                <link>https://example.com/2</link>
                <content:encoded><![CDATA[<p>Second content</p>]]></content:encoded>
              </item>
            </channel>
          </rss>
          XML

        reader = XML::Reader.new(xml)
        parser = Fetcher::StreamingRSSParser.new
        entries = parser.parse_entries(reader, 10)
        entries.size.should eq(2)
        entries[0].content.should contain("World")
        entries[1].content.should contain("Second content")
      end

      it "parses multiple items with mixed self-closing and text children" do
        xml = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Test</title>
              <item>
                <title>One</title>
                <link>https://example.com/1</link>
                <enclosure url="https://example.com/a.mp3" type="audio/mpeg" length="456"/>
                <category>Tech</category>
                <enclosure url="https://example.com/a2.mp3" type="audio/mpeg" length="789"/>
                <comments>https://example.com/1/comments</comments>
              </item>
              <item>
                <title>Two</title>
                <link>https://example.com/2</link>
                <category>News</category>
              </item>
              <item>
                <title>Three</title>
                <link>https://example.com/3</link>
              </item>
            </channel>
          </rss>
          XML

        reader = XML::Reader.new(xml)
        parser = Fetcher::StreamingRSSParser.new
        entries = parser.parse_entries(reader, 10)
        entries.size.should eq(3)
        entries[0].title.should eq("One")
        entries[0].attachments.size.should eq(2)
        entries[0].categories.should contain("Tech")
        entries[0].comment_url.should eq("https://example.com/1/comments")
        entries[1].title.should eq("Two")
        entries[1].categories.should contain("News")
        entries[2].title.should eq("Three")
      end

      it "parses multiple Atom entries with self-closing link and category elements" do
        xml = <<-XML
          <?xml version="1.0"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Test</title>
            <entry>
              <title>First Entry</title>
              <link href="https://example.com/1"/>
              <category term="Ruby"/>
              <category term="Crystal"/>
            </entry>
            <entry>
              <title>Second Entry</title>
              <link href="https://example.com/2"/>
              <category term="News"/>
            </entry>
            <entry>
              <title>Third Entry</title>
              <link href="https://example.com/3"/>
            </entry>
          </feed>
          XML

        reader = XML::Reader.new(xml)
        parser = Fetcher::StreamingRSSParser.new
        entries = parser.parse_entries(reader, 10)
        entries.size.should eq(3)
        entries[0].title.should eq("First Entry")
        entries[0].url.should eq("https://example.com/1")
        entries[0].categories.should contain("Ruby")
        entries[0].categories.should contain("Crystal")
        entries[1].title.should eq("Second Entry")
        entries[1].categories.should contain("News")
        entries[2].title.should eq("Third Entry")
      end

      it "parses Atom entry with author containing text children" do
        xml = <<-XML
          <?xml version="1.0"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Test</title>
            <entry>
              <title>First</title>
              <link href="https://example.com/1"/>
              <author>
                <name>Jane Doe</name>
                <uri>https://example.com/jane</uri>
              </author>
            </entry>
            <entry>
              <title>Second</title>
              <link href="https://example.com/2"/>
              <author>
                <name>John Smith</name>
              </author>
            </entry>
          </feed>
          XML

        reader = XML::Reader.new(xml)
        parser = Fetcher::StreamingRSSParser.new
        entries = parser.parse_entries(reader, 10)
        entries.size.should eq(2)
        entries[0].author.should eq("Jane Doe")
        entries[0].author_url.should eq("https://example.com/jane")
        entries[1].author.should eq("John Smith")
      end

      it "handles empty elements without text content" do
        xml = <<-XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Test</title>
              <item>
                <title></title>
                <link>https://example.com/1</link>
                <description></description>
              </item>
              <item>
                <title>Real Title</title>
                <link>https://example.com/2</link>
              </item>
            </channel>
          </rss>
          XML

        reader = XML::Reader.new(xml)
        parser = Fetcher::StreamingRSSParser.new
        entries = parser.parse_entries(reader, 10)
        entries.size.should eq(2)
        entries[0].title.should eq("Untitled")
        entries[1].title.should eq("Real Title")
      end
    end
  end
end
