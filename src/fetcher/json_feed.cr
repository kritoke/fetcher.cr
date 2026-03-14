require "./entry"
require "./result"
require "./retry"
require "./h2o_http_client"
require "./exceptions"
require "./json_feed_parser"
require "./result_builder"

module Fetcher
  module JSONFeed
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
        parse_feed(response.body, limit)
      when 500..599
        error = Error.server_error(response.status_code, "Server error: #{response.status_code}", url)
        raise HTTPServerError.new(error.message, response.status_code, error)
      else
        error = Error.http(response.status_code, "HTTP #{response.status_code}", url)
        raise HTTPError.new(error.message, response.status_code, error)
      end
    rescue ex : IO::TimeoutError
      error = Error.timeout("Timeout: #{ex.message}", url)
      raise TimeoutError.new(error.message, error)
    rescue ex : H2OHttpClient::DNSError
      error = Error.dns("DNS error: #{ex.message}", url)
      raise DNSError.new(error.message, error)
    rescue ex : JSON::ParseException
      error = Error.invalid_format("JSON parsing error: #{ex.message}", url)
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

    private def self.parse_feed(body : String, limit : Int32) : Result
      parsed = JSON.parse(body)

      version = parsed["version"]?.try(&.as_s)
      return Fetcher.error_result(ErrorKind::InvalidFormat, "Invalid JSON Feed: missing version") unless version
      return Fetcher.error_result(ErrorKind::InvalidFormat, "Unsupported JSON Feed version") unless version.includes?("https://jsonfeed.org/version/")

      begin
        parser = JSONFeedParser.new
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
