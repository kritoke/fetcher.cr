require "./src/fetcher"

# Test integration with existing RSS module
config = Fetcher::RequestConfig.new(use_streaming_parser: true)
puts "Streaming config: #{config.use_streaming_parser}"

# This will use the existing DOM parser since streaming isn't integrated yet
# But it shows the configuration is working
puts "✅ Streaming parser infrastructure ready for integration!"
