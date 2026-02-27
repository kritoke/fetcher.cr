require "http/client"

module Fetcher
  module HTTPClient
    def self.fetch(url : String, headers : ::HTTP::Headers, connect_timeout : Time::Span = 10.seconds, read_timeout : Time::Span = 30.seconds) : ::HTTP::Client::Response
      uri = URI.parse(url)
      client = ::HTTP::Client.new(uri)
      client.connect_timeout = connect_timeout
      client.read_timeout = read_timeout

      client.get(uri.request_target, headers: headers)
    end
  end
end
