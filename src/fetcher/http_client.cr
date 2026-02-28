require "http/client"
require "./time_parser"

module Fetcher
  record Config,
    user_agent : String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    connect_timeout : Time::Span = 10.seconds,
    read_timeout : Time::Span = 30.seconds,
    accept_header : String = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7"

  DEFAULT_CONFIG = Config.new

  class RetriableError < Exception
    def initialize(message : String)
      super(message)
    end
  end

  module HTTPClient
    def self.fetch(url : String, headers : ::HTTP::Headers, config : Config = DEFAULT_CONFIG) : ::HTTP::Client::Response
      uri = URI.parse(url)
      client = ::HTTP::Client.new(uri)
      client.connect_timeout = config.connect_timeout
      client.read_timeout = config.read_timeout

      client.get(uri.request_target, headers: headers)
    end
  end

  module Headers
    def self.build(custom_headers : ::HTTP::Headers, config : Config = DEFAULT_CONFIG) : ::HTTP::Headers
      defaults = ::HTTP::Headers{
        "User-Agent"      => config.user_agent,
        "Accept"          => config.accept_header,
        "Accept-Language" => "en-US,en;q=0.9",
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
