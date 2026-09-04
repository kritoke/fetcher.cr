require "log"
require "socket"
require "uri"
require "./url_validator"

module Fetcher
  # Debug-only diagnostics for Reddit fetches. Kept separate from the
  # fetch coordinator so it can evolve (rate-limit observation, header
  # capture, etc.) without touching request flow.
  #
  # All public entry points are gated on `Log.level(:debug)?` so the
  # expensive work (notably DNS resolution) is skipped when debug
  # logging is disabled.
  module RedditDiagnostics
    # Maximum body bytes included in the non-OK response detail string.
    MAX_BODY_SNIPPET = 512

    # Log the resolved addresses and a header subset before issuing
    # the request. Best-effort: failures are logged at debug level and
    # never raised. The DNS resolution lives inside the log block so it
    # only runs when debug logging is enabled.
    def self.log_fetch(api_url : String, final_headers : ::HTTP::Headers) : Nil
      ::Log.for("fetcher.reddit").debug do
        addresses = resolve_addresses(api_url)
        "Fetching Reddit API #{api_url} from resolved addresses: #{addresses.join(", ")}; " \
          "headers: User-Agent=#{final_headers["User-Agent"]?}, Accept=#{final_headers["Accept"]?}"
      end
    rescue ex
      ::Log.for("fetcher.reddit").debug { "Failed to resolve/log diagnostics for #{api_url}: #{ex.message}" }
    end

    # Build a single-line diagnostic summary of a non-OK response.
    # Always callable; cheap when the caller ignores the result.
    def self.build_response_detail(response) : String
      server = header(response, "server", "Server")
      via = header(response, "via", "Via")
      rate_remaining = header(response, "x-ratelimit-remaining", "X-Ratelimit-Remaining")
      content_type = header(response, "content-type", "Content-Type")
      body_snippet = body_snippet(response)

      parts = ["status=#{response.status_code}"]
      parts << "server=#{server}" if server
      parts << "via=#{via}" if via
      parts << "rate_remaining=#{rate_remaining}" if rate_remaining
      parts << "content_type=#{content_type}" if content_type
      parts << "body=#{body_snippet}" if body_snippet
      parts.join("; ")
    end

    private def self.resolve_addresses(api_url : String) : Array(String)
      host = URI.parse(api_url).host
      return ["no_host"] if host.nil? || host.empty?

      Socket::Addrinfo.resolve(host, URLValidator::DNS_RESOLVE_PORT.to_s, type: Socket::Type::STREAM, protocol: Socket::Protocol::TCP)
        .map(&.ip_address.to_s)
    rescue ex
      ["resolve_failed: #{ex.message}"]
    end

    private def self.header(response, *names : String) : String?
      names.each { |n| return response.headers[n]? if response.headers[n]? }
      nil
    end

    private def self.body_snippet(response) : String?
      body = response.body
      return nil unless body && body.is_a?(String)
      body[0, MAX_BODY_SNIPPET].gsub(/\s+/, " ").strip
    rescue
      nil
    end
  end
end