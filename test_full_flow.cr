require "./src/fetcher/rss"

# Simulate what RSS.perform_fetch does
reddit_xml = <<XML
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
  <title>Crystal</title>
  <link rel="alternate" href="https://old.reddit.com/r/crystal/hot"/>
  <entry>
    <author><name>/u/test</name></author>
    <id>t3_1dtqh5c</id>
    <link href="https://old.reddit.com/r/Crystal/comments/1dtqh5c/test/"/>
    <updated>2024-07-02T16:45:46+00:00</updated>
    <published>2024-07-02T16:45:46+00:00</published>
    <title>Test Post</title>
    <content type="html">Test content</content>
  </entry>
</feed>
XML

# Simulate the parse_feed logic from rss.cr:49-71
xml = XML.parse(reddit_xml, options: XML::ParserOptions::RECOVER |
                                     XML::ParserOptions::NOENT |
                                     XML::ParserOptions::NONET)

puts "=== Testing parse_rss ==="
puts "Root: #{xml.root.try(&.name)}"

# Check if RSS parser would find items
is_rdf = xml.root.try(&.name) == "RDF"
puts "is_rdf: #{is_rdf}"

channel = xml.xpath_node("//*[local-name()='channel']")
puts "channel found: #{channel ? "YES" : "NO"}"

if channel
  item_nodes = is_rdf ? xml.xpath_nodes("//*[local-name()='item']") : channel.xpath_nodes("./*[local-name()='item']")
  puts "RSS items found: #{item_nodes.size}"
end

# Now test parse_atom path
puts "\n=== Testing parse_atom ==="
feed_node = xml.xpath_node("//*[local-name()='feed']")
puts "feed found: #{feed_node ? "YES" : "NO"}"

if feed_node
  entries = feed_node.xpath_nodes("./*[local-name()='entry']")
  puts "Atom entries found: #{entries.size}"

  entries.each_with_index do |entry, i|
    puts "\nEntry #{i + 1}:"

    # Exact code from rss.cr:209-211
    published_str = entry.xpath_node("./*[local-name()='published']").try(&.text) ||
                    entry.xpath_node("./*[local-name()='updated']").try(&.text)
    puts "  published_str: #{published_str.inspect}"

    pub_date = Fetcher::TimeParser.parse(published_str, Fetcher::TimeParser::ATOM_FORMATS)
    puts "  pub_date: #{pub_date.inspect}"
  end
end
