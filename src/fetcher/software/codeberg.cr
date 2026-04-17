require "json"
require "../link_resolver"
require "../error_handler"

module Fetcher
  module Software
    module Codeberg
      def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
        http_client = Fetcher::CrestHttpClient.new(config)
        codeberg_headers = ::HTTP::Headers.new
        codeberg_headers["Accept"] = "application/json"

        if token = config.codeberg_token
          codeberg_headers["Authorization"] = "Bearer #{token}"
        end

        merged = Fetcher::CrestHttpClient.build_headers(codeberg_headers)
        response = http_client.get(provider.api_url, merged)

        ErrorHandler.handle_response(response, provider.api_url) do
          releases = parse_json(response.body, provider.api_url)
          stable_releases = releases.reject do |release|
            release["prerelease"]?.try(&.as_bool) || false
          end

          entries = stable_releases.first(limit).map do |release|
            parse_entry(release, provider)
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

      private def self.parse_json(body : String, url : String) : Array(JSON::Any)
        Array(JSON::Any).from_json(body)
      rescue ex : JSON::ParseException
        error = Error.invalid_format("Invalid JSON from #{url}: #{ex.message}", url)
        raise InvalidFormatError.new(error.message, error)
      end

      private def self.parse_entry(release : JSON::Any, provider : SoftwareProvider) : Entry
        tag = release["tag_name"]?.try(&.as_s) || ""
        name = release["name"]?.try(&.as_s).presence || tag
        published_at = release["published_at"]? || release["created_at"]?
        body = release[provider.body_field]?.try(&.as_s) || ""

        pub_date = TimeParser.parse(published_at.try(&.as_s))
        html_url = release["html_url"]?.try(&.as_s) || release["url"]?.try(&.as_s) || ""

        link_data = LinkResolver.resolve_from_url(html_url)

        Entry.create(
          title: "#{provider.repo} #{name}",
          url: html_url,
          source_type: provider.source_type,
          content: body,
          content_html: body.presence,
          published_at: pub_date,
          version: tag,
          comment_url: link_data.comment_url,
          commentary_url: link_data.commentary_url,
          is_discussion_url: link_data.is_discussion_url
        )
      end
    end
  end
end
