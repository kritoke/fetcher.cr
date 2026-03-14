require "./entry"
require "./result"
require "./retry"
require "./h2o_http_client"
require "./exceptions"
require "./rss_parser"
require "./result_builder"

module Fetcher
  module RSS
    MAX_FEED_SIZE = 10 * 1024 * 1024

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      Fetcher.with_retry(config) do
        perform_fetch(url, headers, limit, config)
      end
    end

    private def self.perform_fetch(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      http_client = Fetcher::H2OHttpClient.new(config)
      response = http_client.get(url, headers)

      case response.status_code
      when 304
        ResultBuilder.success(entries: [] of Entry, etag: response.headers["ETag"]?, last_modified: response.headers["Last-Modified"]?)
      when 200..299
        parse_feed(response.body, url, limit, config)
      when 500..599
        error = Error.server_error(response.status_code, "Server error: #{response.status_code}", url)
        raise FetchError.from_error(error)
      else
        error = Error.http(response.status_code, "HTTP #{response.status_code}", url)
        if (400..499).includes?(response.status_code)
          # Client errors are not retriable
          Fetcher.error_result(error)
        else
          # Other errors might be retriable
          raise FetchError.from_error(error)
        end
      end
    rescue ex : IO::TimeoutError
      error = Error.timeout("Timeout: #{ex.message}", url)
      raise TimeoutError.new(error.message, error)
    rescue ex : H2OHttpClient::DNSError
      error = Error.dns("DNS error: #{ex.message}", url)
      raise DNSError.new(error.message, error)
    rescue ex : XML::Error
      error = Error.invalid_format("XML parsing error: #{ex.message}", url)
      raise InvalidFormatError.new(error.message, error)
    rescue ex : FetchError
      # Re-raise typed exceptions
      raise ex
    rescue ex
      if Fetcher.transient_error?(ex)
        error = Error.unknown(ex.message || "Unknown error", url)
        raise UnknownError.new(error.message, error)
      end
      error = Error.unknown("#{ex.class}: #{ex.message}", url)
      Fetcher.error_result(error)
    end

    private def self.parse_feed(body : String, url : String, limit : Int32, config : RequestConfig) : Result
      return Fetcher.error_result(ErrorKind::InvalidFormat, "Feed too large (>#{Fetcher::SafeFeedProcessor::MAX_FEED_SIZE / (1024 * 1024)}MB)") if body.bytesize > Fetcher::SafeFeedProcessor::MAX_FEED_SIZE

      # Note: Streaming parser integration is experimental and currently disabled
      # TODO: Complete streaming parser implementation in future version
      # if config.use_streaming_parser
      #   # ... streaming implementation would go here ...
      # end

      # Use DOM parser (default and only working implementation)
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
