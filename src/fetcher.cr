require "http/client"
require "./fetcher/entry"
require "./fetcher/result"
require "./fetcher/retry"
require "./fetcher/http_client"
require "./fetcher/rss"
require "./fetcher/reddit"
require "./fetcher/software"

module Fetcher
  DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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
    final_headers = build_headers(headers)
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
    final_headers = build_headers(headers)
    final_headers["If-None-Match"] = etag if etag
    final_headers["If-Modified-Since"] = last_modified if last_modified

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
    RSS.pull(url, build_headers(headers), limit)
  end

  def self.pull_reddit(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100) : Result
    Reddit.pull(url, build_headers(headers), limit)
  end

  def self.pull_software(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100) : Result
    Software.pull(url, build_headers(headers), limit)
  end

  private def self.build_headers(custom_headers : ::HTTP::Headers) : ::HTTP::Headers
    headers = ::HTTP::Headers{
      "User-Agent"      => DEFAULT_USER_AGENT,
      "Accept"          => "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7",
      "Accept-Language" => "en-US,en;q=0.9",
      "Connection"      => "keep-alive",
    }

    custom_headers.each do |key, value|
      headers[key] = value
    end

    headers
  end
end
