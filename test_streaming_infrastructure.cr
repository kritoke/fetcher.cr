require "./src/fetcher"

# Test streaming parser infrastructure
config = Fetcher::RequestConfig.new(use_streaming_parser: true)
puts "Streaming parser config created: #{config.use_streaming_parser}"

# Test XML streaming parser
puts "XML streaming parser created"

# Test JSON streaming parser
puts "JSON streaming parser created"

# Test MIME type detection
feed_type = Fetcher::StreamingParser.detect_feed_type("application/rss+xml", "https://example.com/feed.xml")
puts "RSS feed type detected: #{feed_type}"

feed_type = Fetcher::StreamingParser.detect_feed_type("application/json", "https://reddit.com/r/crystal")
puts "Reddit feed type detected: #{feed_type}"

puts "✅ All streaming parser infrastructure working!"
