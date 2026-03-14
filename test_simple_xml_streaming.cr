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
    <item>
      <title>Test Item 2</title>
      <link>https://example.com/item2</link>
      <pubDate>Mon, 02 Jan 2024 00:00:00 GMT</pubDate>
      <description>Another test item</description>
    </item>
  </channel>
</rss>
XML

# Test simple XML streaming parser
puts "Testing SimpleXMLStreamingParser..."

io = IO::Memory.new(rss_xml)
parser = Fetcher::SimpleXMLStreamingParser.new(10)
entries = parser.parse_entries(io, 10)

puts "Parsed #{entries.size} entries"
if entries.size > 0
  puts "First entry title: #{entries[0].title}"
  puts "First entry URL: #{entries[0].url}"
  puts "Published at: #{entries[0].published_at}"
end

puts "✅ SimpleXMLStreamingParser working!"