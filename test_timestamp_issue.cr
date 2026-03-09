require "./src/fetcher"

# Test 1: Parse actual Reddit Atom feed format
puts "=== Test 1: Reddit Atom Feed ==="
reddit_atom = %(<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
  <title>r/crystal</title>
  <link rel="alternate" href="https://www.reddit.com/r/crystal/hot"/>
  <entry>
    <author><name>/u/testuser</name></author>
    <id>t3_test123</id>
    <link href="https://www.reddit.com/r/crystal/comments/test123/"/>
    <updated>2024-07-02T16:45:46+00:00</updated>
    <published>2024-07-02T16:45:46+00:00</published>
    <title>Test Post Title</title>
    <content type="html">Test content here</content>
  </entry>
  <entry>
    <author><name>/u/testuser2</name></author>
    <id>tst_test456</id>
    <link href="https://www.reddit.com/r/crystal/comments/test456/"/>
    <updated>2024-06-15T10:30:00+00:00</updated>
    <title>Post without published field</title>
    <content type="html">Should use updated field</content>
  </entry>
</feed>)

# Test using the actual RSS module internals via XML parsing
xml = XML.parse(reddit_atom, options: XML::ParserOptions::RECOVER |
                               XML::ParserOptions::NOENT |
                               XML::ParserOptions::NONET)

feed_node = xml.xpath_node("//*[local-name()='feed']")
if feed_node
  entries = feed_node.xpath_nodes("./*[local-name()='entry']")
  entries.each_with_index do |entry, i|
    title = entry.xpath_node("./*[local-name()='title']").try(&.text)
    
    # Exact code from rss.cr:209-211
    published_str = entry.xpath_node("./*[local-name()='published']").try(&.text) ||
                    entry.xpath_node("./*[local-name()='updated']").try(&.text)
    
    pub_date = Fetcher::TimeParser.parse(published_str, Fetcher::TimeParser::ATOM_FORMATS)
    
    puts "Entry #{i + 1}:"
    puts "  Title: #{title}"
    puts "  published_str: #{published_str.inspect}"
    puts "  pub_date: #{pub_date.inspect}"
    puts "  Status: #{pub_date ? "✓ OK" : "✗ NIL"}"
    puts
  end
end

# Test 2: RSS 2.0 format (in case Reddit returns this)
puts "=== Test 2: RSS 2.0 Format ==="
rss_xml = %(<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>Test Feed</title>
    <link>https://example.com</link>
    <item>
      <title>Test Article</title>
      <link>https://example.com/article</link>
      <pubDate>Wed, 15 Jan 2024 10:30:00 +0000</pubDate>
    </item>
    <item>
      <title>Article without pubDate</title>
      <link>https://example.com/article2</link>
    </item>
  </channel>
</rss>)

xml = XML.parse(rss_xml)
channel = xml.xpath_node("//*[local-name()='channel']")
if channel
  items = channel.xpath_nodes("./*[local-name()='item']")
  items.each_with_index do |item, i|
    title = item.xpath_node("./*[local-name()='title']").try(&.text)
    
    # Exact code from rss.cr:125-128
    pub_date_str = item.xpath_node("./*[local-name()='pubDate']").try(&.text) ||
                   item.xpath_node("./*[local-name()='dc:date']").try(&.text) ||
                   item.xpath_node("./*[local-name()='date']").try(&.text)
    
    pub_date = Fetcher::TimeParser.parse(pub_date_str, Fetcher::TimeParser::RSS_FORMATS)
    
    puts "Item #{i + 1}:"
    puts "  Title: #{title}"
    puts "  pub_date_str: #{pub_date_str.inspect}"
    puts "  pub_date: #{pub_date.inspect}"
    puts "  Status: #{pub_date ? "✓ OK" : "✗ NIL"}"
    puts
  end
end
