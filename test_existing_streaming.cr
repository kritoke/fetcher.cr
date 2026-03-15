require "./src/fetcher"

# Simple RSS feed for testing
rss_xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Test Feed</title>
    <link>https://example.com</link>
    <description>Test feed description</description>
    <language>en-us</language>
    <item>
      <title>Test Item 1</title>
      <link>https://example.com/item1</link>
      <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
      <description>Test item description</description>
    </item>
  </channel>
</rss>
XML

# Test existing StreamingRSSParser directly
puts "Testing existing StreamingRSSParser..."

reader = XML::Reader.new(rss_xml)
parser = Fetcher::StreamingRSSParser.new
entries = parser.parse_entries(reader, 10)

puts "Parsed #{entries.size} entries"
if entries.size > 0
  puts "First entry title: #{entries[0].title}"
end

puts "✅ Existing StreamingRSSParser test complete!"
