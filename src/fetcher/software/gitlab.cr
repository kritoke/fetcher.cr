require "json"
require "log"
require "../link_resolver"
require "../error_handler"
require "../time_parser"
require "./release_helpers"

module Fetcher
  module Software
    module GitLab
      include ReleaseHelpers

      def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
        http_client = Fetcher::CrestHttpClient.new(config)
        gitlab_headers = ::HTTP::Headers.new
        gitlab_headers["Accept"] = "application/json"

        if token = config.gitlab_token
          gitlab_headers["PRIVATE-TOKEN"] = token
        end

        merged = Fetcher::CrestHttpClient.build_headers(gitlab_headers)
        response = http_client.get(provider.api_url, merged)

        ErrorHandler.handle_response(response, provider.api_url) do
          releases = parse_json(response.body, provider.api_url)
          stable_releases = releases.reject do |release|
            release["upcoming_release"]?.try(&.as_bool) || false
          end

          entries = stable_releases.first(limit).map do |release|
            parse_entry(release, provider)
          end

          Result.builder
            .entries(entries)
            .etag(response.headers["ETag"]?)
            .last_modified(response.headers["Last-Modified"]?)
            .site_link("#{provider.base_url}/#{provider.repo}")
            .favicon("#{provider.base_url}/favicon.ico")
            .build
        end
      rescue ex : JSON::ParseException | IO::TimeoutError | Socket::Error
        ErrorHandler.handle_network_error(ex, provider.api_url)
      rescue ex
        Log.warn { "Unexpected error in GitLab fetch: #{ex.class} - #{ex.message}" }
        ErrorHandler.handle_network_error(ex, provider.api_url)
      end

      private def self.parse_json(body : String, url : String) : Array(JSON::Any)
        Array(JSON::Any).from_json(body)
      rescue ex : JSON::ParseException
        error = Error.invalid_format("Invalid JSON from #{url}: #{ex.message}", url)
        raise InvalidFormatError.new(error.message, error)
      end

      private def self.parse_entry(release : JSON::Any, provider : SoftwareProvider) : Entry
        tag = extract_tag(release)
        name = extract_name(release)
        published_at = release["released_at"]? || release["created_at"]?
        body = release[provider.body_field]?.try(&.as_s) || ""

        pub_date = TimeParser.parse(published_at.try(&.as_s))
        html_url = extract_html_url(release)

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
