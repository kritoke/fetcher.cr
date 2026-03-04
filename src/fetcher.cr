require "http/client"
require "./fetcher/attachment"
require "./fetcher/author"
require "./fetcher/entry"
require "./fetcher/result"
require "./fetcher/retry"
require "./fetcher/http_client"
require "./fetcher/html_utils"
require "./fetcher/time_parser"
require "./fetcher/source_type"
require "./fetcher/fetch_error"
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

  def self.detect_driver(url : String) : DriverType
    if url.matches?(%r{://(www\.)?reddit\.com/r/}i)
      DriverType::Reddit
    elsif url.matches?(%r{://(www\.)?github\.com/[^/]+/[^/]+/releases}i)
      DriverType::Software
    elsif url.matches?(%r{://(www\.)?gitlab\.com/[^/]+/[^/]+/-/releases}i)
      DriverType::Software
    elsif url.matches?(%r{://(www\.)?codeberg\.org/[^/]+/[^/]+/releases}i)
      DriverType::Software
    elsif url.ends_with?(".json") || url.includes?("/feed.json") || url.includes?("/feeds/json")
      DriverType::JSONFeed
    else
      DriverType::RSS
    end
  end

  def self.pull(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    final_headers = Headers.build(headers)
    driver = detect_driver(url)

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
    base_headers = Headers.build(headers)
    final_headers = Headers.with_cache(base_headers, etag, last_modified)

    driver = detect_driver(url)

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
    RSS.pull(url, Headers.build(headers), limit, config)
  end

  def self.pull_reddit(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    Reddit.pull(url, Headers.build(headers), limit, config)
  end

  def self.pull_software(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    Software.pull(url, Headers.build(headers), limit, config)
  end

  def self.pull_json_feed(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
    JSONFeed.pull(url, Headers.build(headers), limit, config)
  end
end
