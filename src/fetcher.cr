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
require "./fetcher/xml_text_reader"
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

  PATTERN_DRIVERS = {
    REDDIT_URL_PATTERN        => DriverType::Reddit,
    GITHUB_RELEASES_PATTERN   => DriverType::Software,
    GITLAB_RELEASES_PATTERN   => DriverType::Software,
    CODEBERG_RELEASES_PATTERN => DriverType::Software,
    YOUTUBE_CHANNEL_PATTERN   => DriverType::YouTube,
  }

  def self.detect_driver(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, config : RequestConfig = RequestConfig.new) : DriverType
    case config.driver_detection_mode
    when .explicit_only?
      error = Error.invalid_format("Explicit driver required - auto-detection disabled", url)
      raise InvalidFormatError.new(error.message, error)
    when .url_only?
      detect_pattern(url) || detect_ext(url) || DriverType::RSS
    when .content_type?
      detect_content(url, headers, config) || detect_ext(url) || DriverType::RSS
    else # :auto
      driver = detect_pattern(url)
      return driver if driver

      driver = detect_content(url, headers, config)
      return driver if driver

      detect_ext(url) || DriverType::RSS
    end
  end

  private def self.detect_pattern(url : String) : DriverType?
    PATTERN_DRIVERS.each { |pattern, driver| return driver if url.matches?(pattern) }
    nil
  end

  private def self.detect_content(url : String, headers : ::HTTP::Headers, config : RequestConfig) : DriverType?
    head_headers = Fetcher::CrestHttpClient.build_headers(headers)
    http_client = Fetcher::CrestHttpClient.new(config)
    response = http_client.head(url, head_headers)

    content_type = response.headers["content-type"]?.try(&.downcase)
    return nil unless content_type

    classify_content_type(content_type, url)
  rescue ex
    ::Log.for("fetcher").debug { "Content-type detection failed for #{url}: #{ex.class} - #{ex.message}" }
    nil
  end

  private def self.classify_content_type(content_type : String, url : String) : DriverType?
    return DriverType::JSONFeed if content_type.includes?("application/feed+json")
    return detect_ext(url) if content_type.includes?("application/json")
    return DriverType::RSS if rss_type?(content_type)
    nil
  end

  private def self.rss_type?(content_type : String) : Bool
    content_type.includes?("application/rss+xml") ||
      content_type.includes?("application/atom+xml") ||
      content_type.includes?("text/xml") ||
      content_type.includes?("application/xml")
  end

  private def self.detect_ext(url : String) : DriverType?
    if url.ends_with?(".json") || url.includes?("/feed.json") || url.includes?("/feeds/json")
      DriverType::JSONFeed
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

    case driver
    when .rss?       then RSS.pull(url, headers, actual_limit, config)
    when .reddit?    then Reddit.pull(url, headers, actual_limit, config)
    when .software?  then Software.pull(url, headers, actual_limit, config)
    when .json_feed? then JSONFeed.pull(url, headers, actual_limit, config)
    when .you_tube?  then YouTube.pull(url, headers, actual_limit, config)
    else                  RSS.pull(url, headers, actual_limit, config)
    end
  rescue ex
    ErrorHandler.log_error(url, ex, config)
    raise ex
  end

  macro define_pull_method(driver_method, module_name)
    def self.{{ driver_method.id }}(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = Config::DEFAULT_LIMIT, config : RequestConfig = RequestConfig.new) : Result
      {{ module_name.id }}.pull(url, Fetcher::CrestHttpClient.build_headers(headers), Math.min(limit, Config::MAX_LIMIT), config)
    end
  end

  define_pull_method pull_rss, RSS
  define_pull_method pull_reddit, Reddit
  define_pull_method pull_software, Software
  define_pull_method pull_json_feed, JSONFeed
  define_pull_method pull_youtube, YouTube
end
