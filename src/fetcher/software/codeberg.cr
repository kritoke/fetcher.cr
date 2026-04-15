require "json"
require "./atom_parser"

module Fetcher
  module Software
    module Codeberg
      def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
        http_client = Fetcher::CrestHttpClient.new(config)
        request_headers = Fetcher::CrestHttpClient.build_headers(::HTTP::Headers.new)

        result = Software.try_software_api("Codeberg", provider, limit, http_client, request_headers)
        return result if result && result.success?

        result = try_atom_feed(provider, limit, http_client, request_headers)
        return result if result && result.success?

        Fetcher.error_result(ErrorKind::HTTPError, "Codeberg fetch error: No releases found", 404)
      end

      private def self.try_atom_feed(provider : SoftwareProvider, limit : Int32, http_client : CrestHttpClient, headers : ::HTTP::Headers) : Result?
        AtomParser.try_parse(http_client, provider.atom_url, provider, limit)
      rescue ex : DNSError
        Fetcher.error_result(ErrorKind::DNSError, "Codeberg DNS error: #{ex.message}")
      end
    end
  end
end
