require "http/client"
require "./fetcher/attachment"
require "./fetcher/author"
require "./fetcher/entry"
require "./fetcher/result"
require "./fetcher/retry"
require "./fetcher/h2o_http_client"
require "./fetcher/html_utils"
require "./fetcher/time_parser"
require "./fetcher/source_type"
require "./fetcher/fetch_error"
require "./fetcher/exceptions"
require "./fetcher/url_validator"
require "./fetcher/entry_factory"
require "./fetcher/entry_parser"
require "./fetcher/rss_parser"
require "./fetcher/json_feed_parser"
require "./fetcher/result_builder"
require "./fetcher/token_bucket_rate_limiter"
require "./fetcher/safe_feed_processor"
require "./fetcher/rss"
require "./fetcher/reddit"
require "./fetcher/software"
require "./fetcher/json_feed"
require "./fetcher/concurrent_fetcher"
require "./fetcher/domain_batch_processor"
require "./fetcher/request_config"
require "./fetcher/streaming_parser"
require "./fetcher/entry_iterator"
require "./fetcher/streaming_fallback"
require "./fetcher/xml_streaming_parser"
require "./fetcher/json_streaming_parser"
require "./fetcher/simple_xml_streaming_parser"

module Fetcher
  enum DriverType
    RSS
    Reddit
    Software
    JSONFeed
  end

  def self.detect_driver(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, config : RequestConfig = RequestConfig.new) : DriverType
    # First, try to detect based on URL patterns for known sources
    driver = detect_by_url_pattern(url)
    return driver if driver

    # For other URLs, use content-type detection
    driver = detect_by_content_type(url, headers, config)
    return driver if driver

    # Final fallback based on URL extension/patterns
    detect_by_url_extension(url)
  end

  private def self.detect_by_url_pattern(url : String) : DriverType?
    if url.matches?(%r{://(www\.)?reddit\.com/r/}i)
      DriverType::Reddit
    elsif url.matches?(%r{://(www\.)?github\.com/[^/]+/[^/]+/releases}i)
      DriverType::Software
    elsif url.matches?(%r{://[^/]+/[^/]+/[^/]+/-/releases}i)
      DriverType::Software
    elsif url.matches?(%r{://(www\.)?codeberg\.org/[^/]+/[^/]+/releases}i)
      DriverType::Software
    end
  end

  private def self.detect_by_content_type(url : String, headers : ::HTTP::Headers, config : RequestConfig) : DriverType?
    begin
      head_headers = Fetcher::H2OHttpClient.build_headers(headers)
      http_client = Fetcher::H2OHttpClient.new(config)
      response = http_client.head(url, head_headers)

      content_type = response.headers["content-type"]?.try(&.downcase)

      if content_type
        if json_feed_content_type?(content_type, url)
          return DriverType::JSONFeed
        elsif rss_content_type?(content_type)
          return DriverType::RSS
        end
      end
    rescue
      # If HEAD request fails, return nil to use fallback
    end

    nil
  end

  private def self.json_feed_content_type?(content_type : String, url : String) : Bool
    content_type.includes?("application/feed+json") ||
      (content_type.includes?("application/json") &&
        (url.ends_with?(".json") || url.includes?("/feed.json") || url.includes?("/feeds/json")))
  end

  private def self.rss_content_type?(content_type : String) : Bool
    content_type.includes?("application/rss+xml") ||
      content_type.includes?("application/atom+xml") ||
      content_type.includes?("text/xml") ||
      content_type.includes?("application/xml")
  end

  private def self.detect_by_url_extension(url : String) : DriverType
    if url.ends_with?(".json") || url.includes?("/feed.json") || url.includes?("/feeds/json")
      DriverType::JSONFeed
    else
      DriverType::RSS
    end
  end

  def self.pull(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    final_headers = Fetcher::H2OHttpClient.build_headers(headers)
    driver = detect_driver(url, final_headers, config)

    case driver
    in .rss?
      RSS.pull(url, final_headers, limit, config)
    in .reddit?
      Reddit.pull(url, final_headers, limit, config)
    in .software?
      Software.pull(url, final_headers, limit, config)
    in .json_feed?
      JSONFeed.pull(url, final_headers, limit, config)
    end
  end

  # Async version of pull
  def self.pull_async(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Channel(Result)
    channel = Channel(Result).new
    spawn do
      begin
        result = pull(url, headers, limit, config)
        channel.send(result)
      rescue ex
        error_result = Fetcher.error_result(ErrorKind::Unknown, "Async fetch error: #{ex.message}")
        channel.send(error_result)
      end
    end
    channel
  end

  def self.pull(url : String, headers : ::HTTP::Headers, etag : String?, last_modified : String?, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    base_headers = Fetcher::H2OHttpClient.build_headers(headers)
    final_headers = Fetcher::H2OHttpClient.with_cache(base_headers, etag, last_modified)

    driver = detect_driver(url, final_headers, config)

    case driver
    in .rss?
      RSS.pull(url, final_headers, limit, config)
    in .reddit?
      Reddit.pull(url, final_headers, limit, config)
    in .software?
      Software.pull(url, final_headers, limit, config)
    in .json_feed?
      JSONFeed.pull(url, final_headers, limit, config)
    end
  end

  # Async version with cache headers
  def self.pull_async(url : String, headers : ::HTTP::Headers, etag : String?, last_modified : String?, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Channel(Result)
    channel = Channel(Result).new
    spawn do
      begin
        result = pull(url, headers, etag, last_modified, limit, config)
        channel.send(result)
      rescue ex
        error_result = Fetcher.error_result(ErrorKind::Unknown, "Async fetch error: #{ex.message}")
        channel.send(error_result)
      end
    end
    channel
  end

  def self.pull_rss(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    RSS.pull(url, Fetcher::H2OHttpClient.build_headers(headers), limit, config)
  end

  # Async version
  def self.pull_rss_async(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Channel(Result)
    channel = Channel(Result).new
    spawn do
      begin
        result = pull_rss(url, headers, limit, config)
        channel.send(result)
      rescue ex
        error_result = Fetcher.error_result(ErrorKind::Unknown, "Async RSS fetch error: #{ex.message}")
        channel.send(error_result)
      end
    end
    channel
  end

  def self.pull_reddit(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    Reddit.pull(url, Fetcher::H2OHttpClient.build_headers(headers), limit, config)
  end

  # Async version
  def self.pull_reddit_async(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Channel(Result)
    channel = Channel(Result).new
    spawn do
      begin
        result = pull_reddit(url, headers, limit, config)
        channel.send(result)
      rescue ex
        error_result = Fetcher.error_result(ErrorKind::Unknown, "Async Reddit fetch error: #{ex.message}")
        channel.send(error_result)
      end
    end
    channel
  end

  def self.pull_software(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    Software.pull(url, Fetcher::H2OHttpClient.build_headers(headers), limit, config)
  end

  # Async version
  def self.pull_software_async(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Channel(Result)
    channel = Channel(Result).new
    spawn do
      begin
        result = pull_software(url, headers, limit, config)
        channel.send(result)
      rescue ex
        error_result = Fetcher.error_result(ErrorKind::Unknown, "Async software fetch error: #{ex.message}")
        channel.send(error_result)
      end
    end
    channel
  end

  def self.pull_json_feed(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    JSONFeed.pull(url, Fetcher::H2OHttpClient.build_headers(headers), limit, config)
  end

  # Async version
  def self.pull_json_feed_async(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Channel(Result)
    channel = Channel(Result).new
    spawn do
      begin
        result = pull_json_feed(url, headers, limit, config)
        channel.send(result)
      rescue ex
        error_result = Fetcher.error_result(ErrorKind::Unknown, "Async JSON feed fetch error: #{ex.message}")
        channel.send(error_result)
      end
    end
    channel
  end
end
