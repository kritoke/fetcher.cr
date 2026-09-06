require "json"
require "log"
require "../link_resolver"
require "../time_parser"
require "./release_helpers"

module Fetcher
  module Software
    module GitHub
      def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
        http_client = Fetcher::CrestHttpClient.new(config)

        # Try REST API first
        result = try_api(provider, limit, http_client)
        return result if result && result.success? && !result.entries.empty?

        # API failed, rate-limited (403), or returned empty — fall back to Atom feed
        atom_result = Software.try_atom_fallback(provider, limit, http_client, Fetcher::CrestHttpClient.build_headers(headers))
        return atom_result if atom_result && atom_result.success?

        # Return the original API result (even if it was an error)
        result || Fetcher.error_result(ErrorKind::HTTPError, "GitHub fetch error: No releases found", 404)
      rescue ex : JSON::ParseException | IO::TimeoutError | Socket::Error | DNSError | InvalidURLError | SSLError
        ErrorHandler.handle_network_error(ex, provider.api_url)
      rescue ex
        Log.warn { "Unexpected error in GitHub fetch: #{ex.class} - #{ex.message}" }
        ErrorHandler.handle_network_error(ex, provider.api_url)
      end

      private def self.try_api(provider : SoftwareProvider, limit : Int32, http_client : CrestHttpClient) : Result?
        github_headers = ::HTTP::Headers.new
        github_headers["Accept"] = "application/vnd.github.v3+json"
        merged = Fetcher::CrestHttpClient.build_headers(github_headers)

        response = http_client.get(provider.api_url, merged)

        return if response.status_code == 404
        return unless (200..299).includes?(response.status_code)

        releases = parse_json(response.body, provider.api_url)
        stable_releases = releases.reject { |release| ReleaseHelpers.prerelease?(release) }

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
      rescue JSON::ParseException
        Log.debug { "GitHub API JSON parse failed, trying fallback: #{provider.api_url}" }
        nil
      rescue ex : OpenSSL::SSL::Error
        raise DNSError.new("GitHub SSL error: #{ex.message}")
      rescue ex : FetchError
        raise ex
      rescue ex
        Log.warn { "GitHub API request failed, trying fallback: #{ex.class} - #{ex.message}" }
        nil
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
          title: "#{provider.repo_name} #{entry_data.name}",
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
        tag = ReleaseHelpers.extract_tag(release)
        name = ReleaseHelpers.extract_name(release)
        body = release["body"]?.try(&.as_s) || release["description"]?.try(&.as_s) || ""
        html_url = ReleaseHelpers.extract_html_url(release)

        GithubReleaseData.new(
          tag: tag,
          name: name,
          body: body,
          html_url: html_url,
          pub_date: ReleaseHelpers.parse_release_date(release),
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
