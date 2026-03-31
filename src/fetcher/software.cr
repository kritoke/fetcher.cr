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

module Fetcher
  module Software
    # Pre-compiled regex patterns for performance
    GITLAB_RELEASES_PATTERN = %r{https?://([^/]+)/([^/]+/[^/]+)/-/releases}

    struct SoftwareProvider
      getter name : String
      getter base_url : String
      getter repo : String
      getter source_type : SourceType
      getter api_url : String
      getter atom_url : String
      getter atom_fallback_urls : Array(String)

      def initialize(
        @name : String,
        @base_url : String,
        @repo : String,
        @source_type : SourceType,
        @api_url : String,
        @atom_url : String,
        @atom_fallback_urls : Array(String) = [] of String,
      )
      end
    end

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      provider = detect_provider(url)
      return Fetcher.error_result(ErrorKind::InvalidURL, "Unknown software provider") unless provider

      Fetcher.with_retry(config) do
        pull_releases(provider, headers, limit, config)
      end
    end

    private def self.detect_provider(url : String) : SoftwareProvider?
      if url.includes?("github.com") && url.includes?("/releases")
        return unless valid_domain?(url, "github.com")

        repo = extract_repo_path(url, "github.com")
        if repo
          return SoftwareProvider.new(
            name: "github",
            base_url: "https://github.com",
            repo: repo,
            source_type: SourceType::GitHub,
            api_url: "https://api.github.com/repos/#{repo}/releases",
            atom_url: "https://github.com/#{repo}/releases.atom",
          )
        end
      end

      gitlab_match = url.match(GITLAB_RELEASES_PATTERN)
      if gitlab_match
        gitlab_domain = gitlab_match[1]
        return unless valid_domain?(url, gitlab_domain)

        repo = gitlab_match[2]
        base_url = "https://#{gitlab_domain}"
        return SoftwareProvider.new(
          name: "gitlab",
          base_url: base_url,
          repo: repo,
          source_type: SourceType::GitLab,
          api_url: "#{base_url}/api/v4/projects/#{URI.encode_path(repo)}/releases",
          atom_url: "#{base_url}/#{repo}/-/releases.atom",
          atom_fallback_urls: ["#{base_url}/#{repo}/-/tags?format=atom"],
        )
      end

      if url.includes?("codeberg.org") && url.includes?("/releases")
        return unless valid_domain?(url, "codeberg.org")

        repo = extract_repo_path(url, "codeberg.org")
        if repo
          return SoftwareProvider.new(
            name: "codeberg",
            base_url: "https://codeberg.org",
            repo: repo,
            source_type: SourceType::Codeberg,
            api_url: "https://codeberg.org/api/v1/repos/#{repo}/releases",
            atom_url: "https://codeberg.org/#{repo}/releases.atom",
          )
        end
      end

      nil
    end

    private def self.valid_domain?(url : String, expected_domain : String) : Bool
      uri = URI.parse(url)
      host = uri.host.try(&.downcase)
      host == expected_domain.downcase
    rescue URI::Error
      false
    end

    private def self.extract_repo_path(url : String, domain : String) : String?
      pattern = "#{domain}/([^/]+/[^/]+)/?"
      match = url.match(Regex.new(pattern))
      match ? match[1] : nil
    end

    private def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      case provider.name
      when "github"
        pull_github_releases(provider, headers, limit, config)
      else
        pull_generic_releases(provider, headers, limit, config)
      end
    end

    private def self.pull_github_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
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
          site_link: "#{provider.base_url}/#{provider.repo}",
          favicon: "#{provider.base_url}/favicon.ico"
        )
      end
    rescue ex : Exception
      ErrorHandler.handle_network_error(ex, provider.api_url)
    end

    private def self.pull_generic_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      http_client = Fetcher::CrestHttpClient.new(config)
      request_headers = Fetcher::CrestHttpClient.build_headers(::HTTP::Headers.new)

      result = try_provider_api(provider, limit, http_client, request_headers)
      return result if result && result.success?

      # Try primary atom URL
      atom_urls = [provider.atom_url] + provider.atom_fallback_urls
      atom_urls.each do |atom_url|
        begin
          atom_result = try_provider_atom(provider, atom_url, limit, http_client, request_headers)
          return atom_result if atom_result && atom_result.success?
        rescue ex : DNSError
          return Fetcher.error_result(ErrorKind::DNSError, "#{provider.name} SSL error: #{ex.message}")
        end
      end

      Fetcher.error_result(ErrorKind::HTTPError, "#{provider.name} fetch error: No releases found", 404)
    end

    private def self.try_provider_api(provider : SoftwareProvider, limit : Int32, http_client : CrestHttpClient, headers : ::HTTP::Headers) : Result?
      response = http_client.get(provider.api_url, headers)

      return if response.status_code == 404
      return unless (200..299).includes?(response.status_code)

      releases = Array(JSON::Any).from_json(response.body)
      return if releases.empty?

      entries = releases.first(limit).map do |release|
        parse_release_entry(release, provider)
      end

      Result.success(
        entries: entries,
        etag: response.headers["ETag"]?,
        site_link: "#{provider.base_url}/#{provider.repo}",
        favicon: "#{provider.base_url}/favicon.ico"
      )
    rescue JSON::ParseException
      ::Log.for("fetcher.software").debug { "#{provider.name} API JSON parse failed, trying fallback: #{provider.api_url}" }
      nil
    rescue ex : OpenSSL::SSL::Error
      raise DNSError.new("#{provider.name} SSL error: #{ex.message}")
    rescue ex : FetchError
      raise ex
    rescue ex
      ::Log.for("fetcher.software").debug { "#{provider.name} API request failed, trying fallback: #{ex.class} - #{ex.message}" }
      nil
    end

    private def self.try_provider_atom(provider : SoftwareProvider, atom_url : String, limit : Int32, http_client : CrestHttpClient, headers : ::HTTP::Headers) : Result?
      response = http_client.get(atom_url, headers)

      return if response.status_code == 404
      return unless (200..299).includes?(response.status_code)

      entries = parse_software_atom_entries(response.body, provider.source_type, limit)
      return if entries.empty?

      Result.success(
        entries: entries,
        etag: response.headers["ETag"]?,
        last_modified: response.headers["Last-Modified"]?,
        site_link: "#{provider.base_url}/#{provider.repo}",
        favicon: "#{provider.base_url}/favicon.ico"
      )
    rescue ex : OpenSSL::SSL::Error
      raise DNSError.new("#{provider.name} SSL error: #{ex.message}")
    rescue ex : FetchError
      raise ex
    rescue ex
      ::Log.for("fetcher.software").debug { "#{provider.name} atom feed failed: #{ex.class} - #{ex.message}" }
      nil
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

      html_url = extract_release_url(release, provider)

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

    private def self.extract_release_url(release : JSON::Any, provider : SoftwareProvider) : String
      case provider.name
      when "github"
        release["html_url"]?.try(&.as_s) || ""
      when "gitlab"
        links = release["_links"]?.try(&.as_h?)
        tag = release["tag_name"]?.try(&.as_s) || ""
        links.try(&.["self"]?).try(&.as_s) || "#{provider.base_url}/#{provider.repo}/-/releases/#{tag}"
      else
        release["html_url"]?.try(&.as_s) || release["url"]?.try(&.as_s) || ""
      end
    end

    private def self.parse_software_atom_entries(body : String, source_type : SourceType, limit : Int32) : Array(Entry)
      parser = RSSParser.new
      entries = parser.parse_entries(body, limit)
      entries.map do |entry|
        # Add version from title if not already present
        version = entry.version || extract_version_from_title(entry.title)
        if version != entry.version
          Entry.create(
            title: entry.title,
            url: entry.url,
            source_type: source_type,
            content: entry.content,
            content_html: entry.content_html,
            author: entry.author,
            author_url: entry.author_url,
            published_at: entry.published_at,
            categories: entry.categories,
            attachments: entry.attachments,
            version: version,
          )
        else
          Entry.create(
            title: entry.title,
            url: entry.url,
            source_type: source_type,
            content: entry.content,
            content_html: entry.content_html,
            author: entry.author,
            author_url: entry.author_url,
            published_at: entry.published_at,
            categories: entry.categories,
            attachments: entry.attachments,
          )
        end
      end
    rescue XML::Error
      [] of Entry
    end

    private def self.extract_version_from_title(title : String) : String?
      match = title.match(/v?\d+\.\d+(?:\.\d+)?(?:[-._]?\w+)?/)
      match ? match[0] : nil
    end
  end
end
