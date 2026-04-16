require "json"
require "../error_handler"
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
      rescue ex : Exception
        ErrorHandler.handle_network_error(ex, provider.api_url)
      end

      private def self.try_atom_feed(provider : SoftwareProvider, limit : Int32, http_client : CrestHttpClient, headers : ::HTTP::Headers) : Result?
        atom_urls = [provider.atom_url] + provider.atom_fallback_urls
        atom_urls.each do |atom_url|
          begin
            atom_result = AtomParser.try_parse(http_client, atom_url, provider, limit)
            return atom_result if atom_result && atom_result.success?
          rescue ex : DNSError
            return Fetcher.error_result(ErrorKind::DNSError, "Codeberg DNS error: #{ex.message}")
          rescue ex
            ::Log.for("fetcher.software").debug { "Codeberg atom feed failed for #{atom_url}: #{ex.class} - #{ex.message}" }
          end
        end
        nil
      end
    end
  end
end
