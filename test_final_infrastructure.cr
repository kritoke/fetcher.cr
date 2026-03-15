require "./src/fetcher"

# Test streaming parser configuration and infrastructure
config = Fetcher::RequestConfig.new(
  use_streaming_parser: true,
  max_streaming_memory: 5_000_000, # 5MB
  debug_streaming: false
)

puts "✅ Streaming parser configuration:"
puts "  use_streaming_parser: #{config.use_streaming_parser}"
puts "  max_streaming_memory: #{config.max_streaming_memory}"
puts "  debug_streaming: #{config.debug_streaming}"

# Test MIME type detection
feed_types = [
  {content_type: "application/rss+xml", url: "https://example.com/feed.xml"},
  {content_type: "application/json", url: "https://reddit.com/r/crystal.json"},
  {content_type: "application/atom+xml", url: "https://example.com/atom.xml"},
  {content_type: nil, url: "https://example.com/feed.json"},
]

feed_types.each do |test|
  detected = Fetcher::StreamingParser.detect_feed_type(test[:content_type], test[:url])
  puts "  Detected '#{test[:url]}' as: #{detected}"
end

puts "✅ Streaming parser infrastructure is ready for full implementation!"
