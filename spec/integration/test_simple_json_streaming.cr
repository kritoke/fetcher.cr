require "./src/fetcher"

# Simple Reddit JSON for testing
reddit_json = <<-JSON
  {
    "data": {
      "children": [
        {
          "data": {
            "title": "Test Reddit Post 1",
            "url": "https://example.com/reddit1",
            "permalink": "/r/test/comments/123",
            "created_utc": 1704067200.0,
            "is_self": false
          }
        },
        {
          "data": {
            "title": "Test Reddit Post 2",
            "url": "https://example.com/reddit2",
            "permalink": "/r/test/comments/456",
            "created_utc": 1704153600.0,
            "is_self": true
          }
        }
      ]
    }
  }
  JSON

# Test JSON streaming parser
puts "Testing SimpleJSONStreamingParser..."

io = IO::Memory.new(reddit_json)
parser = Fetcher::SimpleJSONStreamingParser.new(10)
entries = parser.parse_entries(io, 10)

puts "Parsed #{entries.size} entries"
if entries.size > 0
  puts "First entry title: #{entries[0].title}"
  puts "First entry URL: #{entries[0].url}"
  puts "Published at: #{entries[0].published_at}"
end

puts "✅ SimpleJSONStreamingParser working!"
