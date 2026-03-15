require "crest"
require "./request_config"
require "./token_bucket_rate_limiter"

module Fetcher
  class CrestHttpClient
    DEFAULT_USER_AGENT    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    DEFAULT_ACCEPT_HEADER = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7"

    class DNSError < Exception
    end

    @@token_bucket_limiters = {} of String => TokenBucketRateLimiter
    @@limiters_lock = Mutex.new

    @@http_clients = {} of String => ::HTTP::Client
    @@client_lock = Mutex.new

    def self.get_http_client(host : String, config : RequestConfig) : ::HTTP::Client
      @@client_lock.synchronize do
        client = @@http_clients[host]?
        unless client
          client = ::HTTP::Client.new(URI.parse("https://#{host}"))
          client.connect_timeout = config.connect_timeout
          client.read_timeout = config.read_timeout
          @@http_clients[host] = client
        end
        client
      end
    end

    def self.get_token_bucket_limiter(domain : String, config : RequestConfig) : TokenBucketRateLimiter
      @@limiters_lock.synchronize do
        @@token_bucket_limiters[domain] ||= TokenBucketRateLimiter.new(
          config.rate_limit_capacity,
          config.rate_limit_refill_rate
        )
      end
    end

    def initialize(@config : RequestConfig = RequestConfig.new)
    end

    def head(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Client::Response
      uri = URI.parse(url)
      host = uri.host || "default"

      domain = uri.host || "default"
      rate_limiter = self.class.get_token_bucket_limiter(domain, @config)
      rate_limiter.acquire

      http_client = self.class.get_http_client(host, @config)
      crest_headers = build_crest_headers(headers)

      response = Crest.head(url, headers: crest_headers, http_client: http_client)
      convert_response(response)
    rescue ex : URI::Error
      raise DNSError.new("Invalid URL: #{ex.message}")
    rescue ex : Socket::Error
      raise DNSError.new("DNS/Connection error: #{ex.message}")
    rescue ex : IO::TimeoutError
      raise ex
    rescue ex : Crest::RequestFailed
      raise DNSError.new("HTTP error: #{ex.response.status_code}")
    end

    def get(url : String, headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Client::Response
      uri = URI.parse(url)
      host = uri.host || "default"

      domain = uri.host || "default"
      rate_limiter = self.class.get_token_bucket_limiter(domain, @config)
      rate_limiter.acquire

      http_client = self.class.get_http_client(host, @config)
      crest_headers = build_crest_headers(headers)

      response = Crest.get(url, headers: crest_headers, http_client: http_client)

      if response.body.bytesize > SafeFeedProcessor::MAX_FEED_SIZE
        raise DNSError.new("Response too large (>#{SafeFeedProcessor::MAX_FEED_SIZE / (1024 * 1024)}MB)")
      end

      convert_response(response)
    rescue ex : URI::Error
      raise DNSError.new("Invalid URL: #{ex.message}")
    rescue ex : Socket::Error
      raise DNSError.new("DNS/Connection error: #{ex.message}")
    rescue ex : IO::TimeoutError
      raise ex
    rescue ex : Crest::RequestFailed
      raise DNSError.new("HTTP error: #{ex.response.status_code}")
    end

    private def convert_response(crest_response : Crest::Response) : ::HTTP::Client::Response
      ::HTTP::Client::Response.new(
        status_code: crest_response.status_code,
        body: crest_response.body,
        headers: ::HTTP::Headers.new.merge!(crest_response.headers)
      )
    end

    private def build_crest_headers(headers : ::HTTP::Headers) : Hash(String, String)
      result = HTTP::Headers{
        "User-Agent"      => DEFAULT_USER_AGENT,
        "Accept"          => DEFAULT_ACCEPT_HEADER,
        "Accept-Language" => "en-US,en;q=0.9",
        "Connection"      => "keep-alive",
      }
      result.merge!(headers)

      hash = Hash(String, String).new
      result.each do |key, value|
        hash[key] = value.is_a?(Array) ? value.join(", ") : value.to_s
      end
      hash
    end

    def self.build_headers(custom_headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Headers
      defaults = ::HTTP::Headers{
        "User-Agent"      => DEFAULT_USER_AGENT,
        "Accept"          => DEFAULT_ACCEPT_HEADER,
        "Accept-Language" => "en-US,en;q=0.9",
        "Connection"      => "keep-alive",
      }

      result = defaults.dup
      result.merge!(custom_headers)
      result
    end

    def self.with_cache(base : ::HTTP::Headers, etag : String?, last_modified : String?) : ::HTTP::Headers
      result = base.dup
      result["If-None-Match"] = etag if etag
      result["If-Modified-Since"] = last_modified if last_modified
      result
    end
  end
end
