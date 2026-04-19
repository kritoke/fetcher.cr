require "json"
require "xml"
require "uri"
require "./entry"
require "./result"
require "./retry"
require "./crest_http_client"
require "./time_parser"
require "./exceptions"
require "./error_handler"
require "./rss_parser"
require "./link_resolver"
require "./software/github"
require "./software/gitlab"
require "./software/codeberg"
require "./software/atom_parser"

module Fetcher
  module Software
    GITHUB_RELEASES_PATTERN   = %r{https?://(?:www\.)?github\.com/([^/]+/[^/]+)(?:/[^/]*)*/releases}
    CODEBERG_RELEASES_PATTERN = %r{https?://(?:www\.)?codeberg\.org/([^/]+/[^/]+)(?:/[^/]*)*/releases}
    GITLAB_RELEASES_PATTERN   = %r{https?://([^/.]+\.[^/]+)/([^/]+/[^/]+)/-/releases}

    struct SoftwareProvider
      getter name : String
      getter base_url : String
      getter repo : String
      getter source_type : SourceType
      getter api_url : String
      getter atom_url : String
      getter atom_fallback_urls : Array(String)
      getter body_field : String

      def initialize(
        @name : String,
        @base_url : String,
        @repo : String,
        @source_type : SourceType,
        @api_url : String,
        @atom_url : String,
        @atom_fallback_urls : Array(String) = [] of String,
        @body_field : String = "body",
      )
      end
    end

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      provider = detect(url)
      return Fetcher.error_result(ErrorKind::InvalidURL, "Unknown software provider") unless provider

      Fetcher.with_retry(config) do
        pull_releases(provider, headers, limit, config)
      end
    end

    private def self.detect(url : String) : SoftwareProvider?
      if _ = url.match(GITHUB_RELEASES_PATTERN)
        return unless valid_domain?(url, "github.com")
        repo = extract_repo(url, "github.com")
        return build_github_provider(repo) if repo
      end

      if match = url.match(GITLAB_RELEASES_PATTERN)
        gitlab_domain = match[1]
        return unless valid_domain?(url, gitlab_domain)
        repo = match[2]
        base_url = "https://#{gitlab_domain}"
        return SoftwareProvider.new(
          name: "gitlab",
          base_url: base_url,
          repo: repo,
          source_type: SourceType::GitLab,
          api_url: "#{base_url}/api/v4/projects/#{repo.split('/').map { |segment| URI.encode_path(segment) }.join('/')}/releases",
          atom_url: "#{base_url}/#{repo}/-/releases.atom",
          atom_fallback_urls: ["#{base_url}/#{repo}/-/tags?format=atom"],
          body_field: "description",
        )
      end

      if _ = url.match(CODEBERG_RELEASES_PATTERN)
        return unless valid_domain?(url, "codeberg.org")
        repo = extract_repo(url, "codeberg.org")
        return build_codeberg_provider(repo) if repo
      end

      nil
    end

    private def self.build_github_provider(repo : String) : SoftwareProvider
      SoftwareProvider.new(
        name: "github",
        base_url: "https://github.com",
        repo: repo,
        source_type: SourceType::GitHub,
        api_url: "https://api.github.com/repos/#{repo}/releases",
        atom_url: "https://github.com/#{repo}/releases.atom",
      )
    end

    private def self.build_codeberg_provider(repo : String) : SoftwareProvider
      SoftwareProvider.new(
        name: "codeberg",
        base_url: "https://codeberg.org",
        repo: repo,
        source_type: SourceType::Codeberg,
        api_url: "https://codeberg.org/api/v1/repos/#{repo}/releases",
        atom_url: "https://codeberg.org/#{repo}/releases.atom",
      )
    end

    private def self.valid_domain?(url : String, expected_domain : String) : Bool
      uri = URI.parse(url)
      host = uri.host.try(&.downcase)
      host == expected_domain.downcase
    rescue URI::Error
      false
    end

    private def self.extract_repo(url : String, domain : String) : String?
      pattern = "#{domain}/([^/]+/[^/]+)/?"
      match = url.match(Regex.new(pattern))
      match ? match[1] : nil
    end

    private def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      case provider.name
      when "github"
        GitHub.pull_releases(provider, headers, limit, config)
      when "gitlab"
        GitLab.pull_releases(provider, headers, limit, config)
      when "codeberg"
        Codeberg.pull_releases(provider, headers, limit, config)
      else
        Fetcher.error_result(ErrorKind::InvalidURL, "Unknown software provider")
      end
    end

    def self.try_software_api(provider_name : String, provider : SoftwareProvider, limit : Int32, http_client : CrestHttpClient, headers : ::HTTP::Headers) : Result?
      response = http_client.get(provider.api_url, headers)

      return if response.status_code == 404
      return unless (200..299).includes?(response.status_code)

      releases = Array(JSON::Any).from_json(response.body)
      return if releases.empty?

      entries = releases.first(limit).map do |release|
        parse_software_entry(release, provider, provider.body_field)
      end

      Result.success(
        entries: entries,
        etag: response.headers["ETag"]?,
        last_modified: response.headers["Last-Modified"]?,
        site_link: "#{provider.base_url}/#{provider.repo}",
        favicon: "#{provider.base_url}/favicon.ico"
      )
    rescue JSON::ParseException
      ::Log.for("fetcher.software").debug { "#{provider_name} API JSON parse failed, trying fallback: #{provider.api_url}" }
      nil
    rescue ex : OpenSSL::SSL::Error
      raise DNSError.new("#{provider_name} SSL error: #{ex.message}")
    rescue ex : FetchError
      raise ex
    rescue ex
      ::Log.for("fetcher.software").debug { "#{provider_name} API request failed, trying fallback: #{ex.class} - #{ex.message}" }
      nil
    end

    def self.parse_software_entry(release : JSON::Any, provider : SoftwareProvider, body_field : String = "body") : Entry
      tag = release["tag_name"]?.try(&.as_s) || ""
      name = release["name"]?.try(&.as_s).presence || tag
      published_at = release["published_at"]? || release["released_at"]? || release["created_at"]?
      body = release[body_field]?.try(&.as_s) || ""

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

    def self.try_releases_sequence(
      provider_name : String,
      provider : SoftwareProvider,
      limit : Int32,
      http_client : CrestHttpClient,
      headers : ::HTTP::Headers,
    ) : Result
      result = try_software_api(provider_name, provider, limit, http_client, headers)
      return result if result && result.success?

      result = try_atom_fallback(provider, limit, http_client, headers)
      return result if result && result.success?

      Fetcher.error_result(ErrorKind::HTTPError, "#{provider_name} fetch error: No releases found", 404)
    rescue ex : Exception
      ErrorHandler.handle_network_error(ex, provider.api_url)
    end

    def self.try_atom_fallback(provider : SoftwareProvider, limit : Int32, http_client : CrestHttpClient, headers : ::HTTP::Headers) : Result?
      atom_urls = [provider.atom_url] + provider.atom_fallback_urls
      atom_urls.each do |atom_url|
        begin
          atom_result = AtomParser.try_parse(http_client, atom_url, provider, limit)
          return atom_result if atom_result && atom_result.success?
        rescue ex : DNSError
          return Fetcher.error_result(ErrorKind::DNSError, "#{provider.name} DNS error: #{ex.message}")
        rescue ex
          ::Log.for("fetcher.software").debug { "#{provider.name} atom feed failed for #{atom_url}: #{ex.class} - #{ex.message}" }
        end
      end
      nil
    end
  end
end
