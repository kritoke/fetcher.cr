# Property-based testing for feed parsing
module PropertyTestHelper
  # Test that parsing is idempotent (parsing same data gives same result)
  def self.test_parsing_idempotency(parser : Fetcher::EntryParser, data : String, limit : Int32 = 10)
    result1 = parser.parse_entries(data, limit)
    result2 = parser.parse_entries(data, limit)

    result1.size.should eq(result2.size)
    result1.zip(result2).each do |entry1, entry2|
      entry1.title.should eq(entry2.title)
      entry1.url.should eq(entry2.url)
      entry1.content.should eq(entry2.content)
    end
  end

  # Test that empty feeds return empty results
  def self.test_empty_feed(parser : Fetcher::EntryParser)
    empty_rss = <<-XML
    <?xml version="1.0"?>
    <rss version="2.0"><channel><title>Empty</title></channel></rss>
    XML

    result = parser.parse_entries(empty_rss, 10)
    result.size.should eq(0)
  end

  # Test that invalid feeds raise appropriate errors
  def self.test_invalid_feed_raises_error(parser : Fetcher::EntryParser)
    invalid_xml = "<invalid xml>"
    expect_raises(Fetcher::InvalidFormatError) do
      parser.parse_entries(invalid_xml, 10)
    end
  end

  # Test URL validation in entries
  def self.test_entry_url_validation
    entry = Fetcher::Entry.create(
      title: "Test",
      url: "http://localhost/evil",
      source_type: Fetcher::SourceType::RSS
    )
    entry.url.should eq("#") # Should be blocked by URL validation

    entry2 = Fetcher::Entry.create(
      title: "Test",
      url: "https://example.com/good",
      source_type: Fetcher::SourceType::RSS
    )
    entry2.url.should eq("https://example.com/good")
  end
end
