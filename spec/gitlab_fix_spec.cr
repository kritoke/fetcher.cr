require "spec"
require "../src/fetcher"

describe "GitLab namespace fix" do
  it "parses namespaced Atom entries correctly" do
    atom_xml = <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
          <title>Test Release</title>
          <link href="https://example.com/release"/>
          <updated>2024-01-15T10:30:00Z</updated>
        </entry>
      </feed>
      XML

    xml = XML.parse(atom_xml)
    entries = xml.xpath_nodes("//*[local-name()='entry']")
    entries.size.should eq(1)

    entry = entries[0]
    title_node = entry.xpath_node("./*[local-name()='title']")
    title = title_node.nil? ? "Untitled" : title_node.text
    title.should eq("Test Release")

    link_node = entry.xpath_node("./*[local-name()='link']")
    link = link_node.try(&.[]?("href")).try(&.strip).presence || ""
    link.should eq("https://example.com/release")
  end
end
