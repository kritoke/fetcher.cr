require "./entry"
require "./result"
require "./retry"
require "./crest_http_client"
require "./exceptions"
require "./rss_parser"
require "./result_builder"
require "./xml_streaming_parser"
require "./error_handler"

module Fetcher
  module RSS
    MAX_FEED_SIZE = 10 * 1024 * 1024

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      Fetcher.with_retry(config) do
        perform_fetch(url, headers, limit, config)
      end
    end

    private def self.perform_fetch(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      http_client = Fetcher::CrestHttpClient.new(config)
      response = http_client.get(url, headers)

      ErrorHandler.handle_response(response, url) do
        parse_feed(response.body, url, limit, config)
      end
    rescue ex : Exception
      ErrorHandler.handle_network_error(ex, url)
    end

    private def self.parse_feed(body : String, url : String, limit : Int32, config : RequestConfig) : Result
      return Fetcher.error_result(ErrorKind::InvalidFormat, "Feed too large (>#{Fetcher::SafeFeedProcessor::MAX_FEED_SIZE / (1024 * 1024)}MB)") if body.bytesize > Fetcher::SafeFeedProcessor::MAX_FEED_SIZE

      # Use streaming parser if configured
      if config.use_streaming_parser
        begin
          io = IO::Memory.new(body)
          parser = Fetcher::XMLStreamingParser.new(limit)
          result = parser.parse_complete(io, limit, config)

          return result if result.success?

          ::Log.for("fetcher.rss").debug { "Streaming parser returned error, falling back to DOM parser" }
        rescue ex : Fetcher::MemoryLimitExceeded
          ::Log.for("fetcher.rss").debug { "Streaming parser memory limit exceeded, cannot fallback" }
          return Fetcher.error_result(ErrorKind::InvalidFormat, ex.message || "Feed too large for streaming parser")
        rescue ex
          ::Log.for("fetcher.rss").debug { "Streaming parser failed: #{ex.class} - #{ex.message}, falling back to DOM parser" }
        end
      end

      # Use DOM parser (default and fallback implementation)
      begin
        parser = RSSParser.new
        entries = parser.parse_entries(body, limit)
        metadata = parser.parse_feed_metadata(body)

        ResultBuilder.success(
          entries: entries,
          site_link: metadata[:site_link],
          favicon: metadata[:favicon],
          feed_title: metadata[:feed_title],
          feed_description: metadata[:feed_description],
          feed_language: metadata[:feed_language],
          feed_authors: metadata[:feed_authors]
        )
      rescue ex : InvalidFormatError
        Fetcher.error_result(ErrorKind::InvalidFormat, ex.message || "Invalid format error")
      rescue ex
        Fetcher.error_result(ErrorKind::Unknown, "Error: #{ex.class} - #{ex.message}")
      end
    end
  end
end
