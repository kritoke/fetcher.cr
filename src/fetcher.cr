require "http/client"
require "./fetcher/entry"
require "./fetcher/result"
require "./fetcher/retry"
require "./fetcher/http_client"
require "./fetcher/rss"
require "./fetcher/reddit"
require "./fetcher/software"

module Fetcher
  enum DriverType
    RSS
    Reddit
    Software
  end

  def self.detect_driver(url : String) : DriverType
    if url.includes?("reddit.com/r/")
      DriverType::Reddit
    elsif url.includes?("github.com") && url.includes?("/releases")
      DriverType::Software
    elsif url.includes?("gitlab.com") && url.includes?("/-/releases")
      DriverType::Software
    elsif url.includes?("codeberg.org") && url.includes?("/releases")
      DriverType::Software
    else
      DriverType::RSS
    end
  end

  def self.pull(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100) : Result
    final_headers = Headers.build(headers)
    driver = detect_driver(url)

    case driver
    in .rss?
      RSS.pull(url, final_headers, limit)
    in .reddit?
      Reddit.pull(url, final_headers, limit)
    in .software?
      Software.pull(url, final_headers, limit)
    end
  end

  def self.pull(url : String, headers : ::HTTP::Headers, etag : String?, last_modified : String?, limit : Int32 = 100) : Result
    base_headers = Headers.build(headers)
    final_headers = Headers.with_cache(base_headers, etag, last_modified)

    driver = detect_driver(url)

    case driver
    in .rss?
      RSS.pull(url, final_headers, limit)
    in .reddit?
      Reddit.pull(url, final_headers, limit)
    in .software?
      Software.pull(url, final_headers, limit)
    end
  end

  def self.pull_rss(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100) : Result
    RSS.pull(url, Headers.build(headers), limit)
  end

  def self.pull_reddit(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100) : Result
    Reddit.pull(url, Headers.build(headers), limit)
  end

  def self.pull_software(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100) : Result
    Software.pull(url, Headers.build(headers), limit)
  end
end
