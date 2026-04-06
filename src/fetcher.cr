require "http/client"
require "./fetcher/config"
require "./fetcher/attachment"
require "./fetcher/author"
require "./fetcher/entry"
require "./fetcher/result"
require "./fetcher/retry"
require "./fetcher/crest_http_client"
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
require "./fetcher/token_bucket_rate_limiter"
require "./fetcher/circuit_breaker"
require "./fetcher/cache"
require "./fetcher/safe_feed_processor"
require "./fetcher/concurrent_fetcher"
require "./fetcher/domain_batch_processor"
require "./fetcher/request_config"
require "./fetcher/entry_iterator"
require "./fetcher/xml_streaming_parser"
require "./fetcher/json_streaming_parser"
require "./fetcher/error_handler"
require "./fetcher/rss"
require "./fetcher/reddit"
require "./fetcher/software"
require "./fetcher/json_feed"
require "./fetcher/youtube"

module Fetcher
  # Pre-compiled regex patterns for performance
  REDDIT_URL_PATTERN        = %r{://(www\.)?reddit\.com/r/}i
  GITHUB_RELEASES_PATTERN   = %r{://(www\.)?github\.com/[^/]+/[^/]+/releases}i
  CODEBERG_RELEASES_PATTERN = %r{://(www\.)?codeberg\.org/[^/]+/[^/]+/releases}i
  YOUTUBE_CHANNEL_PATTERN   = %r{://(www\.)?youtube\.com/channel/}i
  GITLAB_RELEASES_PATTERN   = %r{://[^/]+/[^/]+/[^/]+/-/releases}i

  enum DriverType
    RSS
    Reddit
    Software
    JSONFeed
    YouTube
  end

  def self.detect_driver(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, config : RequestConfig = RequestConfig.new) : DriverType
    case config.driver_detection_mode
    when .explicit_only?
      error = Error.invalid_format("Explicit driver required - auto-detection disabled", url)
      raise InvalidFormatError.new(error.message, error)
    when .url_only?
      detect_by_url_pattern(url) || detect_by_url_extension(url) || DriverType::RSS
    when .content_type?
      detect_by_content_type(url, headers, config) || detect_by_url_extension(url) || DriverType::RSS
    else # :auto
      # First, try to detect based on URL patterns for known sources
      driver = detect_by_url_pattern(url)
      return driver if driver

      # For other URLs, use content-type detection
      driver = detect_by_content_type(url, headers, config)
      return driver if driver

      # Final fallback based on URL extension/patterns
      detect_by_url_extension(url) || DriverType::RSS
    end
  end

  private def self.detect_by_url_pattern(url : String) : DriverType?
    if url.matches?(REDDIT_URL_PATTERN)
      DriverType::Reddit
    elsif url.matches?(GITHUB_RELEASES_PATTERN)
      DriverType::Software
    elsif url.matches?(GITLAB_RELEASES_PATTERN)
      DriverType::Software
    elsif url.matches?(CODEBERG_RELEASES_PATTERN)
      DriverType::Software
    elsif url.matches?(YOUTUBE_CHANNEL_PATTERN)
      DriverType::YouTube
    end
  end

  private def self.detect_by_content_type(url : String, headers : ::HTTP::Headers, config : RequestConfig) : DriverType?
    begin
      head_headers = Fetcher::CrestHttpClient.build_headers(headers)
      http_client = Fetcher::CrestHttpClient.new(config)
      response = http_client.head(url, head_headers)

      content_type = response.headers["content-type"]?.try(&.downcase)

      if content_type
        if json_feed_content_type?(content_type, url)
          return DriverType::JSONFeed
        elsif rss_content_type?(content_type)
          return DriverType::RSS
        end
      end
    rescue ex
      ::Log.for("fetcher").debug { "Content-type detection failed for #{url}: #{ex.class} - #{ex.message}" }
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

  private def self.detect_by_url_extension(url : String) : DriverType?
    if url.ends_with?(".json") || url.includes?("/feed.json") || url.includes?("/feeds/json")
      DriverType::JSONFeed
    else
      nil
    end
  end

  def self.pull(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = Config::DEFAULT_LIMIT, config : RequestConfig = RequestConfig.new) : Result
    execute_pull(url, headers, limit, config)
  end

  def self.pull(url : String, headers : ::HTTP::Headers, etag : String?, last_modified : String?, limit : Int32 = Config::DEFAULT_LIMIT, config : RequestConfig = RequestConfig.new) : Result
    base_headers = Fetcher::CrestHttpClient.build_headers(headers)
    final_headers = Fetcher::CrestHttpClient.with_cache(base_headers, etag, last_modified)
    execute_pull(url, final_headers, limit, config)
  end

  private def self.execute_pull(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
    actual_limit = Math.min(limit, Config::MAX_LIMIT)
    driver = detect_driver(url, headers, config)

    ::Log.for("fetcher").debug { "Pulling URL #{url} with driver #{driver}" }

    begin
      case driver
      in .rss?
        RSS.pull(url, headers, actual_limit, config)
      in .reddit?
        Reddit.pull(url, headers, actual_limit, config)
      in .software?
        Software.pull(url, headers, actual_limit, config)
      in .json_feed?
        JSONFeed.pull(url, headers, actual_limit, config)
      in .you_tube?
        YouTube.pull(url, headers, actual_limit, config)
      end
    rescue ex
      ErrorHandler.log_error(url, ex, config)
      raise ex
    end
  end

  def self.pull_rss(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = Config::DEFAULT_LIMIT, config : RequestConfig = RequestConfig.new) : Result
    RSS.pull(url, Fetcher::CrestHttpClient.build_headers(headers), Math.min(limit, Config::MAX_LIMIT), config)
  end

  def self.pull_reddit(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = Config::DEFAULT_LIMIT, config : RequestConfig = RequestConfig.new) : Result
    Reddit.pull(url, Fetcher::CrestHttpClient.build_headers(headers), Math.min(limit, Config::MAX_LIMIT), config)
  end

  def self.pull_software(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = Config::DEFAULT_LIMIT, config : RequestConfig = RequestConfig.new) : Result
    Software.pull(url, Fetcher::CrestHttpClient.build_headers(headers), Math.min(limit, Config::MAX_LIMIT), config)
  end

  def self.pull_json_feed(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = Config::DEFAULT_LIMIT, config : RequestConfig = RequestConfig.new) : Result
    JSONFeed.pull(url, Fetcher::CrestHttpClient.build_headers(headers), Math.min(limit, Config::MAX_LIMIT), config)
  end

  def self.pull_youtube(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = Config::DEFAULT_LIMIT, config : RequestConfig = RequestConfig.new) : Result
    YouTube.pull(url, Fetcher::CrestHttpClient.build_headers(headers), Math.min(limit, Config::MAX_LIMIT), config)
  end
end
