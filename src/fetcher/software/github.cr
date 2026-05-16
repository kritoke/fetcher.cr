require "json"
require "log"
require "../link_resolver"
require "../time_parser"
require "./release_helpers"

module Fetcher
  module Software
    module GitHub
      include ReleaseHelpers

      def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
        github_headers = ::HTTP::Headers.new
        github_headers["Accept"] = "application/vnd.github.v3+json"
        merged = Fetcher::CrestHttpClient.build_headers(github_headers)

        http_client = Fetcher::CrestHttpClient.new(config)
        response = http_client.get(provider.api_url, merged)

        ErrorHandler.handle_response(response, provider.api_url) do
          releases = parse_json(response.body, provider.api_url)
          stable_releases = releases.reject { |release| prerelease?(release) }

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
        Log.warn { "Unexpected error in GitHub fetch: #{ex.class} - #{ex.message}" }
        ErrorHandler.handle_network_error(ex, provider.api_url)
      end

      private def self.parse_json(body : String, url : String) : Array(JSON::Any)
        Array(JSON::Any).from_json(body)
      rescue ex : JSON::ParseException
        error = Error.invalid_format("Invalid JSON from #{url}: #{ex.message}", url)
        raise InvalidFormatError.new(error.message, error)
      end

      private def self.parse_entry(release : JSON::Any, provider : SoftwareProvider) : Entry
        entry_data = extract_release_data(release, provider)

        Entry.create(
          title: "#{provider.repo} #{entry_data.name}",
          url: entry_data.html_url,
          source_type: provider.source_type,
          content: entry_data.body,
          content_html: entry_data.body.presence,
          published_at: entry_data.pub_date,
          version: entry_data.tag,
          comment_url: entry_data.link_data.comment_url,
          commentary_url: entry_data.link_data.commentary_url,
          is_discussion_url: entry_data.link_data.is_discussion_url
        )
      end

      private def self.extract_release_data(release : JSON::Any, provider : SoftwareProvider) : GithubReleaseData
        tag = extract_tag(release)
        name = extract_name(release)
        body = release["body"]?.try(&.as_s) || release["description"]?.try(&.as_s) || ""
        html_url = extract_html_url(release)

        GithubReleaseData.new(
          tag: tag,
          name: name,
          body: body,
          html_url: html_url,
          pub_date: parse_release_date(release),
          link_data: LinkResolver.resolve_from_url(html_url)
        )
      end

      record GithubReleaseData,
        tag : String,
        name : String,
        body : String,
        html_url : String,
        pub_date : Time?,
        link_data : LinkResolver::LinkData
    end
  end
end