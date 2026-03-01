require "http/client"
require "./request_config"

module Fetcher
  module HTTPClient
    DEFAULT_USER_AGENT      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    DEFAULT_ACCEPT_HEADER   = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7"
    DEFAULT_CONNECT_TIMEOUT = 10.seconds
    DEFAULT_READ_TIMEOUT    = 30.seconds

    def self.fetch(url : String, headers : ::HTTP::Headers, config : RequestConfig = RequestConfig.new) : ::HTTP::Client::Response
      uri = URI.parse(url)
      client = ::HTTP::Client.new(uri)
      client.connect_timeout = config.connect_timeout
      client.read_timeout = config.read_timeout

      client.get(uri.request_target, headers: headers)
    end
  end

  module Headers
    def self.build(custom_headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Headers
      defaults = ::HTTP::Headers{
        "User-Agent"      => HTTPClient::DEFAULT_USER_AGENT,
        "Accept"          => HTTPClient::DEFAULT_ACCEPT_HEADER,
        "Accept-Language" => "en-US,en;q=0.9",
        "Accept-Encoding" => "gzip, deflate",
        "Connection"      => "keep-alive",
      }

      defaults.merge!(custom_headers.dup)
    end

    def self.with_cache(base : ::HTTP::Headers, etag : String?, last_modified : String?) : ::HTTP::Headers
      result = base.dup
      result["If-None-Match"] = etag if etag
      result["If-Modified-Since"] = last_modified if last_modified
      result
    end
  end
end
