require "./entry"
require "./result"
require "./retry"
require "./crest_http_client"
require "./exceptions"
require "./rss_parser"
require "./result_builder"
require "./xml_streaming_parser"

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
    rescue ex : CrestHttpClient::DNSError
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

      # Use streaming parser if configured
      if config.use_streaming_parser
        begin
          io = IO::Memory.new(body)
          parser = Fetcher::XMLStreamingParser.new(limit)
          result = parser.parse_complete(io, limit, config)
          
          # If streaming parser returns success, use it
          return result if result.success?
          
          # If streaming parser fails but doesn't raise, fallback to DOM
          puts "Streaming parser returned error, falling back to DOM parser" if config.debug_streaming
        rescue ex : Fetcher::StreamingErrorHandling::MemoryLimitExceeded
          # Don't fallback for memory issues - this would cause OOM
          puts "Streaming parser memory limit exceeded, cannot fallback" if config.debug_streaming
          return Fetcher.error_result(ErrorKind::InvalidFormat, ex.message || "Feed too large for streaming parser")
        rescue ex
          # Log fallback if debug enabled
          puts "Streaming parser failed: #{ex.class} - #{ex.message}, falling back to DOM parser" if config.debug_streaming
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
