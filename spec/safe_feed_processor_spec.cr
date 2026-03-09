require "spec"
require "../src/fetcher/safe_feed_processor"
require "../src/fetcher/fetch_error"
require "../src/fetcher/exceptions"
require "../src/fetcher/entry"

describe Fetcher::SafeFeedProcessor do
  it "rejects feeds larger than MAX_FEED_SIZE" do
    large_content = "x" * (Fetcher::SafeFeedProcessor::MAX_FEED_SIZE + 1)

    expect_raises(Fetcher::InvalidFormatError, "Feed too large") do
      Fetcher::SafeFeedProcessor.process_feed(large_content, 10) do |content|
        [] of Fetcher::Entry
      end
    end
  end

  it "processes feeds within size limit" do
    small_content = "x" * (Fetcher::SafeFeedProcessor::MAX_FEED_SIZE - 1)

    result = Fetcher::SafeFeedProcessor.process_feed(small_content, 10) do |content|
      [Fetcher::Entry.create("Test", "https://example.com", Fetcher::SourceType::RSS)]
    end

    result.size.should eq(1)
  end

  it "handles XML parsing with size limit" do
    xml_content = <<-XML
    <?xml version="1.0"?>
    <rss version="2.0">
      <channel>
        <title>Test</title>
        <item>
          <title>Item 1</title>
          <link>https://example.com</link>
        </item>
      </channel>
    </rss>
    XML

    result = Fetcher::SafeFeedProcessor.process_feed(xml_content, 10) do |content|
      # Parse XML content normally
      xml = XML.parse(content)
      entries = [] of Fetcher::Entry

      item_nodes = xml.xpath_nodes("//item")
      item_nodes.each do |item|
        title_node = item.xpath_node("title")
        title = (title_node && !title_node.text.strip.empty?) ? title_node.text : "Untitled"
        link_node = item.xpath_node("link")
        link = (link_node && !link_node.text.strip.empty?) ? link_node.text : "#"
        entries << Fetcher::Entry.create(title, link, Fetcher::SourceType::RSS)
      end

      entries
    end

    result.size.should eq(1)
    result[0].title.should eq("Item 1")
  end

  it "handles JSON parsing with size limit" do
    json_content = %({"items": [{"title": "Test", "url": "https://example.com"}]})

    result = Fetcher::SafeFeedProcessor.process_json_feed(json_content, 10) do |content|
      parsed = JSON.parse(content)
      items = [] of Fetcher::Entry

      parsed["items"].as_a.each do |item|
        title = item["title"].as_s
        url = item["url"].as_s
        items << Fetcher::Entry.create(title, url, Fetcher::SourceType::JSONFeed)
      end

      items
    end

    result.size.should eq(1)
    result[0].title.should eq("Test")
  end
end
