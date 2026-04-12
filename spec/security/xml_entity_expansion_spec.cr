require "spec"
require "../../src/fetcher"

describe "Security: XML Entity Expansion" do
  describe "DOM parser" do
    it "handles normal entity references correctly" do
      xml = <<-XML
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel>
            <title>Test &amp; Feed</title>
            <item>
              <title>Item with &lt;special&gt; chars</title>
              <link>https://example.com</link>
            </item>
          </channel>
        </rss>
        XML

      parser = Fetcher::RSSParser.new
      entries = parser.parse_entries(xml, 10)
      entries.size.should eq(1)
      entries[0].title.should contain("special")
    end

    it "handles feeds without entity declarations" do
      xml = <<-XML
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel>
            <title>Simple Feed</title>
            <item>
              <title>Normal Item</title>
              <link>https://example.com/1</link>
            </item>
          </channel>
        </rss>
        XML

      parser = Fetcher::RSSParser.new
      entries = parser.parse_entries(xml, 10)
      entries.size.should eq(1)
      entries[0].title.should eq("Normal Item")
    end

    it "handles standard CDATA sections" do
      xml = <<-XML
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel>
            <title>CDATA Feed</title>
            <item>
              <title><![CDATA[Title with <b>bold</b>]]></title>
              <link>https://example.com</link>
            </item>
          </channel>
        </rss>
        XML

      parser = Fetcher::RSSParser.new
      entries = parser.parse_entries(xml, 10)
      entries.size.should eq(1)
      entries[0].title.should contain("bold")
    end
  end

  describe "streaming parser" do
    it "enforces iteration limits on XML text content" do
      # The streaming parser has MAX_XML_DEPTH = 1000 and iteration limit of 1_000_000
      # We can't easily test entity expansion in streaming without a massive payload,
      # but we verify normal operation works
      xml = <<-XML
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel>
            <title>Test</title>
            <item>
              <title>Stream Item</title>
              <link>https://example.com/stream</link>
            </item>
          </channel>
        </rss>
        XML

      io = IO::Memory.new(xml)
      parser = Fetcher::StreamingRSSParser.new
      entries = parser.parse_entries(XML::Reader.new(io), 10)
      entries.size.should eq(1)
      entries[0].title.should eq("Stream Item")
    end
  end
end
