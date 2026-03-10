require "http/client"
require "./fetcher/attachment"
require "./fetcher/author"
require "./fetcher/entry"
require "./fetcher/result"
require "./fetcher/retry"
require "./fetcher/http_client_v2"
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
require "./fetcher/request_config"

module Fetcher
  enum DriverType
    RSS
    Reddit
    Software
    JSONFeed
  end

  def self.detect_driver(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, config : RequestConfig = RequestConfig.new) : DriverType
    # First, try to detect based on URL patterns for known sources
    if url.matches?(%r{://(www\.)?reddit\.com/r/}i)
      return DriverType::Reddit
    elsif url.matches?(%r{://(www\.)?github\.com/[^/]+/[^/]+/releases}i)
      return DriverType::Software
    elsif url.matches?(%r{://[^/]+/[^/]+/[^/]+/-/releases}i)
      return DriverType::Software
    elsif url.matches?(%r{://(www\.)?codeberg\.org/[^/]+/[^/]+/releases}i)
      return DriverType::Software
    end

    # For other URLs, use content-type detection
    begin
      head_headers = Fetcher::HttpClient.build_headers(headers)
      http_client = Fetcher::HttpClient.new(config)
      response = http_client.head(url, head_headers)

      content_type = response.headers["content-type"]?.try(&.downcase)

      if content_type
        if content_type.includes?("application/feed+json") ||
           (content_type.includes?("application/json") &&
           (url.ends_with?(".json") || url.includes?("/feed.json") || url.includes?("/feeds/json")))
          return DriverType::JSONFeed
        elsif content_type.includes?("application/rss+xml") ||
              content_type.includes?("application/atom+xml") ||
              content_type.includes?("text/xml") ||
              content_type.includes?("application/xml")
          return DriverType::RSS
        end
      end
    rescue
      # If HEAD request fails, fall back to URL-based detection
    end

    # Final fallback based on URL extension/patterns
    if url.ends_with?(".json") || url.includes?("/feed.json") || url.includes?("/feeds/json")
      DriverType::JSONFeed
    else
      DriverType::RSS
    end
  end

  def self.pull(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    final_headers = Fetcher::HttpClient.build_headers(headers)
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

  def self.pull(url : String, headers : ::HTTP::Headers, etag : String?, last_modified : String?, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    base_headers = Fetcher::HttpClient.build_headers(headers)
    final_headers = Fetcher::HttpClient.with_cache(base_headers, etag, last_modified)

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

  def self.pull_rss(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    RSS.pull(url, Fetcher::HttpClient.build_headers(headers), limit, config)
  end

  def self.pull_reddit(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    Reddit.pull(url, Fetcher::HttpClient.build_headers(headers), limit, config)
  end

  def self.pull_software(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    Software.pull(url, Fetcher::HttpClient.build_headers(headers), limit, config)
  end

  def self.pull_json_feed(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    JSONFeed.pull(url, Fetcher::HttpClient.build_headers(headers), limit, config)
  end
end
