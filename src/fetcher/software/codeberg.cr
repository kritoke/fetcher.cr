require "json"
require "./atom_parser"

module Fetcher
  module Software
    module Codeberg
      def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
        http_client = Fetcher::CrestHttpClient.new(config)
        request_headers = Fetcher::CrestHttpClient.build_headers(::HTTP::Headers.new)

        result = try_api(provider, limit, http_client, request_headers)
        return result if result && result.success?

        result = try_atom_feed(provider, limit, http_client, request_headers)
        return result if result && result.success?

        Fetcher.error_result(ErrorKind::HTTPError, "Codeberg fetch error: No releases found", 404)
      end

      private def self.try_api(provider : SoftwareProvider, limit : Int32, http_client : CrestHttpClient, headers : ::HTTP::Headers) : Result?
        response = http_client.get(provider.api_url, headers)

        return if response.status_code == 404
        return unless (200..299).includes?(response.status_code)

        releases = Array(JSON::Any).from_json(response.body)
        return if releases.empty?

        entries = releases.first(limit).map do |release|
          parse_entry(release, provider)
        end

        Result.success(
          entries: entries,
          etag: response.headers["ETag"]?,
          last_modified: response.headers["Last-Modified"]?,
          site_link: "#{provider.base_url}/#{provider.repo}",
          favicon: "#{provider.base_url}/favicon.ico"
        )
      rescue JSON::ParseException
        ::Log.for("fetcher.software").debug { "Codeberg API JSON parse failed, trying fallback: #{provider.api_url}" }
        nil
      rescue ex : OpenSSL::SSL::Error
        raise DNSError.new("Codeberg SSL error: #{ex.message}")
      rescue ex : FetchError
        raise ex
      rescue ex
        ::Log.for("fetcher.software").debug { "Codeberg API request failed, trying fallback: #{ex.class} - #{ex.message}" }
        nil
      end

      private def self.try_atom_feed(provider : SoftwareProvider, limit : Int32, http_client : CrestHttpClient, headers : ::HTTP::Headers) : Result?
        AtomParser.try_parse(http_client, provider.atom_url, provider, limit)
      rescue ex : DNSError
        Fetcher.error_result(ErrorKind::DNSError, "Codeberg SSL error: #{ex.message}")
      end

      private def self.parse_entry(release : JSON::Any, provider : SoftwareProvider) : Entry
        tag = release["tag_name"]?.try(&.as_s) || ""
        name = release["name"]?.try(&.as_s).presence || tag
        published_at = release["published_at"]? || release["released_at"]? || release["created_at"]?
        body = release["body"]?.try(&.as_s) || ""

        pub_date = TimeParser.parse_iso8601(published_at.try(&.as_s))
        html_url = release["html_url"]?.try(&.as_s) || release["url"]?.try(&.as_s) || ""

        Entry.create(
          title: "#{provider.repo} #{name}",
          url: html_url,
          source_type: provider.source_type,
          content: body,
          content_html: body.presence,
          published_at: pub_date,
          version: tag
        )
      end
    end
  end
end
