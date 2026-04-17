require "json"
require "../error_handler"
require "./atom_parser"

module Fetcher
  module Software
    module GitLab
      def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
        http_client = Fetcher::CrestHttpClient.new(config)
        request_headers = Fetcher::CrestHttpClient.build_headers(::HTTP::Headers.new)

        Software.try_releases_sequence("GitLab", provider, limit, http_client, request_headers)
      end
    end
  end
end
