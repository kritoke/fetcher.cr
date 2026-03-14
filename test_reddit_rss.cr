require "xml"
require "./src/fetcher/time_parser"

# Simulate Reddit Atom feed entry parsing
atom_xml = %(<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <author><name>/u/test</name></author>
    <id>t3_1dtqh5c</id>
    <link href="https://www.reddit.com/r/Crystal/comments/1dtqh5c/test/"/>
    <updated>2024-07-02T16:45:46+00:00</updated>
    <published>2024-07-02T16:45:46+00:00</published>
    <title>Test Post</title>
    <content type="html">Test content</content>
  </entry>
</feed>)

xml = XML.parse(atom_xml)
entry = xml.xpath_node("//*[local-name()='entry']")

if entry
  # Simulate the exact code from rss.cr:209-211
  published_str = entry.xpath_node("./*[local-name()='published']").try(&.text) ||
                  entry.xpath_node("./*[local-name()='updated']").try(&.text)

  puts "Raw published_str: #{published_str.inspect}"

  # Simulate TimeParser.parse call from rss.cr:211
  pub_date = Fetcher::TimeParser.parse(published_str, Fetcher::TimeParser::ATOM_FORMATS)

  puts "Parsed pub_date: #{pub_date.inspect}"
end
