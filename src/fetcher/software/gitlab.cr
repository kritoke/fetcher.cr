require "json"
require "./atom_parser"

module Fetcher
  module Software
    module GitLab
      def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
        http_client = Fetcher::CrestHttpClient.new(config)
        request_headers = Fetcher::CrestHttpClient.build_headers(::HTTP::Headers.new)

        result = Software.try_software_api("GitLab", provider, limit, http_client, request_headers)
        return result if result && result.success?

        result = try_atom(provider, limit, http_client, request_headers)
        return result if result && result.success?

        Fetcher.error_result(ErrorKind::HTTPError, "GitLab fetch error: No releases found", 404)
      end

      private def self.try_atom(provider : SoftwareProvider, limit : Int32, http_client : CrestHttpClient, headers : ::HTTP::Headers) : Result?
        atom_urls = [provider.atom_url] + provider.atom_fallback_urls
        atom_urls.each do |atom_url|
          begin
            atom_result = AtomParser.try_parse(http_client, atom_url, provider, limit)
            return atom_result if atom_result && atom_result.success?
          rescue ex : DNSError
            return Fetcher.error_result(ErrorKind::DNSError, "GitLab DNS error: #{ex.message}")
          end
        end
        nil
      end
    end
  end
end
