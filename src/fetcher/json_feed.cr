require "log"
require "./entry"
require "./result"
require "./retry"
require "./crest_http_client"
require "./exceptions"
require "./json_feed_parser"
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
    rescue ex : DNSError | InvalidURLError | SSLError | TimeoutError | IO::TimeoutError | Socket::Error
      ErrorHandler.handle_network_error(ex, url)
    rescue ex
      Log.warn { "JSON feed fetch unexpected error: #{ex.class} - #{ex.message}" }
      ErrorHandler.handle_network_error(ex, url)
    end

    private def self.parse_feed(body : String, limit : Int32, config : RequestConfig) : Result
      parsed = JSON.parse(body)

      version = parsed["version"]?.try(&.as_s)
      return Fetcher.error_result(ErrorKind::InvalidFormat, "Invalid JSON Feed: missing version") unless version
      return Fetcher.error_result(ErrorKind::InvalidFormat, "Unsupported JSON Feed version") unless version.starts_with?("https://jsonfeed.org/version/")

      begin
        parser = JSONFeedParser.new
        entries = parser.parse_entries(parsed, limit)
        metadata = parser.parse_feed_metadata(parsed)

        Result.builder
          .entries(entries)
          .site_link(metadata.site_link)
          .favicon(metadata.favicon)
          .feed_title(metadata.feed_title)
          .feed_description(metadata.feed_description)
          .feed_language(metadata.feed_language)
          .feed_authors(metadata.feed_authors)
          .build
      rescue ex : InvalidFormatError
        Fetcher.error_result(ErrorKind::InvalidFormat, ex.message || "Invalid format error")
      rescue ex
        Fetcher.error_result(ErrorKind::Unknown, "Error: #{ex.class} - #{ex.message}")
      end
    end
  end
end
