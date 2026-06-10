module Fetcher
  module HeaderBuilder
    DEFAULT_USER_AGENT    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    DEFAULT_ACCEPT_HEADER = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7"

    def self.build(custom_headers : ::HTTP::Headers = ::HTTP::Headers.new) : ::HTTP::Headers
      result = ::HTTP::Headers{
        "User-Agent"      => DEFAULT_USER_AGENT,
        "Accept"          => DEFAULT_ACCEPT_HEADER,
        "Accept-Language" => "en-US,en;q=0.9",
        "Connection"      => "keep-alive",
      }
      result.merge!(custom_headers)
      result
    end

    def self.build_for_crest(custom_headers : ::HTTP::Headers = ::HTTP::Headers.new) : Hash(String, String)
      headers = build(custom_headers)
      hash = Hash(String, String).new
      headers.each do |key, value|
        hash[key] = value.is_a?(Array) ? value.join(", ") : value.to_s
      end
      hash
    end

    # Add conditional If-None-Match / If-Modified-Since headers so a client
    # can revalidate against a previously-issued ETag or Last-Modified value.
    # Both arguments are optional; the corresponding header is only added when
    # the value is present.
    def self.with_cache(base : ::HTTP::Headers, etag : String?, last_modified : String?) : ::HTTP::Headers
      result = base.dup
      result["If-None-Match"] = etag if etag
      result["If-Modified-Since"] = last_modified if last_modified
      result
    end
  end
end
