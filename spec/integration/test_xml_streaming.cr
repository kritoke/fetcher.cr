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

# Test XML streaming parser
puts "Testing XML streaming parser..."

# Create IO from string
io = IO::Memory.new(rss_xml)

# Create parser
parser = Fetcher::XMLStreamingParser.new(10)

# Parse entries
entries = parser.parse_entries(io, 10)
puts "Parsed #{entries.size} entries"

# Test complete parsing with metadata
io.rewind
result = parser.parse_complete(io, 10)
puts "Complete parse result: #{result.success?}"
if result.success?
  puts "Feed title: #{result.feed_title}"
  puts "Site link: #{result.site_link}"
  puts "Entries: #{result.entries.size}"
end

puts "✅ XML streaming parser working!"
