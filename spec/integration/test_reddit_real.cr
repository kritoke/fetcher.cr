require "xml"
require "./src/fetcher/time_parser"

# Actual Reddit feed structure from old.reddit.com/r/crystal/hot.rss
reddit_xml = <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
    <category term="Crystal" label="r/Crystal"/>
    <updated>2026-03-06T12:12:22+00:00</updated>
    <icon>https://www.redditstatic.com/icon.png/</icon>
    <id>/r/crystal/hot.rss</id>
    <link rel="self" href="https://old.reddit.com/r/crystal/hot.rss" type="application/atom+xml" />
    <link rel="alternate" href="https://old.reddit.com/r/crystal/hot" type="text/html" />
    <subtitle>This community is no longer in use.</subtitle>
    <title>Crystal</title>
    <entry>
      <author>
        <name>/u/Hopeful-Humanbeing</name>
        <uri>https://old.reddit.com/user/Hopeful-Humanbeing</uri>
      </author>
      <category term="Crystal" label="r/Crystal"/>
      <content type="html">test content</content>
      <id>t3_1dtqh5c</id>
      <link href="https://old.reddit.com/r/Crystal/comments/1dtqh5c/crystal_identification/" />
      <updated>2024-07-02T16:45:46+00:00</updated>
      <published>2024-07-02T16:45:46+00:00</published>
      <title>Crystal Identification?!</title>
    </entry>
  </feed>
XML

xml = XML.parse(reddit_xml)

# Check root element
puts "Root name: #{xml.root.try(&.name)}"
puts "Root namespace: #{xml.root.try(&.namespace)}"

# Try to find entries
entries = xml.xpath_nodes("//*[local-name()='entry']")
puts "\nEntries found: #{entries.size}"

entries.each_with_index do |entry, i|
  puts "\n--- Entry #{i + 1} ---"

  # Simulate exact code from rss.cr:209-211
  published_str = entry.xpath_node("./*[local-name()='published']").try(&.text) ||
                  entry.xpath_node("./*[local-name()='updated']").try(&.text)

  puts "published_str: #{published_str.inspect}"

  # Simulate TimeParser.parse call
  pub_date = Fetcher::TimeParser.parse(published_str, Fetcher::TimeParser::ATOM_FORMATS)
  puts "pub_date: #{pub_date.inspect}"
end
