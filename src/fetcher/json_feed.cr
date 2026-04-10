require "./entry"
require "./result"
require "./retry"
require "./crest_http_client"
require "./exceptions"
require "./json_feed_parser"
require "./json_streaming_parser"
require "./error_handler"

module Fetcher
  module JSONFeed
    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      Fetcher.with_retry(config) do
        fetch(url, headers, limit, config)
      end
    end

    private def self.fetch(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      http_client = Fetcher::CrestHttpClient.new(config)
      response = http_client.get(url, headers)

      ErrorHandler.handle_response(response, url) do
        parse_feed(response.body, limit, config)
      end
    rescue ex : Exception
      ErrorHandler.handle_network_error(ex, url)
    end

    private def self.parse_feed(body : String, limit : Int32, config : RequestConfig) : Result
      # Try streaming parser first if configured
      if config.streaming.enabled
        begin
          io = IO::Memory.new(body)
          parser = Fetcher::JSONStreamingParser.new(limit)
          entries = parser.parse_entries(io, limit)

          # For JSON Feed, we need to extract metadata separately
          # For now, return minimal metadata
          return Result.success(
            entries: entries,
            site_link: nil,
            favicon: nil,
            feed_title: nil,
            feed_description: nil,
            feed_language: nil,
            feed_authors: [] of Author
          )
        rescue ex : Fetcher::MemoryLimitExceeded
          ::Log.for("fetcher.jsonfeed").debug { "JSON Feed streaming parser memory limit exceeded, cannot fallback" }
          return Fetcher.error_result(ErrorKind::InvalidFormat, ex.message || "Feed too large")
        rescue ex
          ::Log.for("fetcher.jsonfeed").debug { "JSON Feed streaming parser failed: #{ex.class} - #{ex.message}, falling back to DOM parser" }
        end
      end

      # Fallback to DOM parser
      parsed = JSON.parse(body)

      version = parsed["version"]?.try(&.as_s)
      return Fetcher.error_result(ErrorKind::InvalidFormat, "Invalid JSON Feed: missing version") unless version
      return Fetcher.error_result(ErrorKind::InvalidFormat, "Unsupported JSON Feed version") unless version.starts_with?("https://jsonfeed.org/version/")

      begin
        parser = JSONFeedParser.new
        entries = parser.parse_entries(parsed, limit)
        metadata = parser.parse_feed_metadata(parsed)

        Result.success(
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
