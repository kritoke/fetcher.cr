require "json"

module Fetcher
  module Software
    module GitHub
      def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
        github_headers = ::HTTP::Headers.new
        github_headers["Accept"] = "application/vnd.github.v3+json"
        merged = Fetcher::CrestHttpClient.build_headers(github_headers)

        http_client = Fetcher::CrestHttpClient.new(config)
        response = http_client.get(provider.api_url, merged)

        if response.status_code == 429
          error = Error.rate_limited("GitHub rate limited", provider.api_url)
          raise RateLimitError.new(error.message, error)
        end

        ErrorHandler.handle_response(response, provider.api_url) do
          releases = parse_json_releases(response.body, provider.api_url)
          stable_releases = releases.reject do |release|
            release["prerelease"]?.try(&.as_bool) || release["draft"]?.try(&.as_bool)
          end

          entries = stable_releases.first(limit).map do |release|
            parse_release_entry(release, provider)
          end

          Result.success(
            entries: entries,
            etag: response.headers["ETag"]?,
            last_modified: response.headers["Last-Modified"]?,
            site_link: "#{provider.base_url}/#{provider.repo}",
            favicon: "#{provider.base_url}/favicon.ico"
          )
        end
      rescue ex : Exception
        ErrorHandler.handle_network_error(ex, provider.api_url)
      end

      private def self.parse_json_releases(body : String, url : String) : Array(JSON::Any)
        Array(JSON::Any).from_json(body)
      rescue ex : JSON::ParseException
        error = Error.invalid_format("Invalid JSON from #{url}: #{ex.message}", url)
        raise InvalidFormatError.new(error.message, error)
      end

      private def self.parse_release_entry(release : JSON::Any, provider : SoftwareProvider) : Entry
        tag = release["tag_name"]?.try(&.as_s) || ""
        name = release["name"]?.try(&.as_s).presence || tag
        published_at = release["published_at"]? || release["released_at"]? || release["created_at"]?
        body = release["body"]?.try(&.as_s) || release["description"]?.try(&.as_s) || ""

        pub_date = TimeParser.parse_iso8601(published_at.try(&.as_s))
        html_url = release["html_url"]?.try(&.as_s) || ""

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
