require "json"
require "xml"
require "uri"
require "./entry"
require "./result"
require "./retry"
require "./h2o_http_client"
require "./time_parser"
require "./exceptions"

module Fetcher
  module Software
    alias ProviderInfo = NamedTuple(provider: String, base_url: String, repo: String)

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      info = detect_provider(url)
      return Fetcher.error_result(ErrorKind::InvalidURL, "Unknown software provider") unless info

      Fetcher.with_retry(config) do
        case info[:provider]
        when "github"
          pull_github(url, headers, limit, config)
        when "gitlab"
          pull_gitlab(info, headers, limit, config)
        when "codeberg"
          pull_codeberg(info, headers, limit, config)
        else
          Fetcher.error_result(ErrorKind::InvalidURL, "Unsupported provider")
        end
      end
    end

    private def self.detect_provider(url : String) : ProviderInfo?
      if url.includes?("github.com") && url.includes?("/releases")
        repo = extract_repo_path(url, "github.com")
        return {provider: "github", base_url: "https://github.com", repo: repo} if repo
      end

      gitlab_match = url.match(%r{https?://([^/]+)/([^/]+/[^/]+)/-/releases})
      if gitlab_match
        return {provider: "gitlab", base_url: "https://#{gitlab_match[1]}", repo: gitlab_match[2]}
      end

      if url.includes?("codeberg.org") && url.includes?("/releases")
        repo = extract_repo_path(url, "codeberg.org")
        return {provider: "codeberg", base_url: "https://codeberg.org", repo: repo} if repo
      end

      nil
    end

    private def self.extract_repo_path(url : String, domain : String) : String?
      match = url.match(%r{#{domain}/([^/]+/[^/]+)/?})
      match ? match[1] : nil
    end

    private def self.pull_github(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      repo = extract_repo_path(url, "github.com")
      error_url = url
      return Fetcher.error_result(ErrorKind::InvalidURL, "Invalid GitHub repo URL", nil) unless repo

      api_url = "https://api.github.com/repos/#{repo}/releases"

      github_headers = ::HTTP::Headers.new
      github_headers["Accept"] = "application/vnd.github.v3+json"
      merged = Fetcher::H2OHttpClient.build_headers(github_headers)

      http_client = Fetcher::H2OHttpClient.new(config)
      response = http_client.get(api_url, merged)

      if response.status_code == 429
        error = Error.rate_limited("GitHub rate limited", api_url)
        raise RateLimitError.new(error.message, error)
      end

      return Fetcher.error_result(ErrorKind::HTTPError, "GitHub API error: #{response.status_code}", response.status_code) unless (200..299).includes?(response.status_code)

      begin
        releases = Array(JSON::Any).from_json(response.body)
      rescue ex : JSON::ParseException
        error = Error.invalid_format("Invalid JSON from GitHub: #{ex.message}", api_url)
        raise InvalidFormatError.new(error.message, error)
      end

      stable_releases = releases.reject do |release|
        release["prerelease"]?.try(&.as_bool) || release["draft"]?.try(&.as_bool)
      end

      entries = stable_releases.first(limit).map do |release|
        parse_github_release(release, repo)
      end

      Result.success(
        entries: entries,
        etag: response.headers["ETag"]?,
        site_link: "https://github.com/#{repo}",
        favicon: "https://github.com/favicon.ico"
      )
    rescue ex : IO::TimeoutError
      error = Error.timeout("Timeout: #{ex.message}", error_url)
      raise TimeoutError.new(error.message, error)
    rescue ex : H2OHttpClient::DNSError
      error = Error.dns("DNS error: #{ex.message}", error_url)
      raise DNSError.new(error.message, error)
    rescue ex : FetchError
      raise ex
    rescue ex
      if Fetcher.transient_error?(ex)
        error = Error.unknown(ex.message || "Unknown error", error_url)
        raise UnknownError.new(error.message, error)
      end
      error = Error.unknown("#{ex.class}: #{ex.message}", error_url)
      Fetcher.error_result(error)
    end

    private def self.parse_github_release(release : JSON::Any, repo : String) : Entry
      tag = release["tag_name"]?.try(&.as_s) || ""
      name = release["name"]?.try(&.as_s).presence || tag
      html_url = release["html_url"]?.try(&.as_s) || ""
      published = release["published_at"]?.try(&.as_s)
      body = release["body"]?.try(&.as_s) || ""

      pub_date = TimeParser.parse_iso8601(published)

      Entry.create(
        title: "#{repo} #{name}",
        url: html_url,
        source_type: SourceType::GitHub,
        content: body,
        content_html: body.presence,
        published_at: pub_date,
        version: tag
      )
    end

    private def self.pull_gitlab(info : ProviderInfo, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      base_url = info[:base_url]
      repo = info[:repo]
      error_url = "#{base_url}/#{repo}/-/releases"

      http_client = Fetcher::H2OHttpClient.new(config)
      request_headers = Fetcher::H2OHttpClient.build_headers(::HTTP::Headers.new)

      result = try_gitlab_api(base_url, repo, limit, http_client, request_headers)
      return result if result && result.success?

      result = try_gitlab_releases_atom(base_url, repo, limit, http_client, request_headers)
      return result if result && result.success?

      result = try_gitlab_tags_atom(base_url, repo, limit, http_client, request_headers)
      return result if result

      Fetcher.error_result(ErrorKind::HTTPError, "GitLab fetch error: No releases or tags found", 404)
    end

    private def self.try_gitlab_api(base_url : String, repo : String, limit : Int32, http_client : H2OHttpClient, headers : ::HTTP::Headers) : Result?
      encoded_path = URI.encode_path(repo)
      api_url = "#{base_url}/api/v4/projects/#{encoded_path}/releases"

      begin
        response = http_client.get(api_url, headers)

        return nil if response.status_code == 404
        return nil unless (200..299).includes?(response.status_code)

        releases = Array(JSON::Any).from_json(response.body)
        return nil if releases.empty?

        entries = releases.first(limit).map do |release|
          parse_gitlab_release(release, repo, base_url)
        end

        Result.success(
          entries: entries,
          etag: response.headers["ETag"]?,
          site_link: "#{base_url}/#{repo}",
          favicon: "#{base_url}/favicon.ico"
        )
      rescue ex : JSON::ParseException
        nil
      rescue ex
        nil
      end
    end

    private def self.parse_gitlab_release(release : JSON::Any, repo : String, base_url : String) : Entry
      tag = release["tag_name"]?.try(&.as_s) || ""
      name = release["name"]?.try(&.as_s).presence || tag
      released_at = release["released_at"]? || release["created_at"]?
      description = release["description"]?.try(&.as_s) || ""

      links = release["_links"]?.try(&.as_h?)
      html_url = links.try(&.["self"]?).try(&.as_s) || "#{base_url}/#{repo}/-/releases/#{tag}"

      pub_date = TimeParser.parse_iso8601(released_at.try(&.as_s))

      Entry.create(
        title: "#{repo} #{name}",
        url: html_url,
        source_type: SourceType::GitLab,
        content: description,
        content_html: description.presence,
        published_at: pub_date,
        version: tag
      )
    end

    private def self.try_gitlab_releases_atom(base_url : String, repo : String, limit : Int32, http_client : H2OHttpClient, headers : ::HTTP::Headers) : Result?
      atom_url = "#{base_url}/#{repo}/-/releases.atom"

      begin
        response = http_client.get(atom_url, headers)

        return nil if response.status_code == 404
        return nil unless (200..299).includes?(response.status_code)

        entries = parse_atom_entries(response.body, "gitlab", limit)
        return nil if entries.empty?

        Result.success(
          entries: entries,
          etag: response.headers["ETag"]?,
          last_modified: response.headers["Last-Modified"]?,
          site_link: "#{base_url}/#{repo}",
          favicon: "#{base_url}/favicon.ico"
        )
      rescue ex
        nil
      end
    end

    private def self.try_gitlab_tags_atom(base_url : String, repo : String, limit : Int32, http_client : H2OHttpClient, headers : ::HTTP::Headers) : Result?
      tags_url = "#{base_url}/#{repo}/-/tags?format=atom"

      begin
        response = http_client.get(tags_url, headers)

        return nil if response.status_code == 404
        return nil unless (200..299).includes?(response.status_code)

        entries = parse_atom_entries(response.body, "gitlab", limit)
        return nil if entries.empty?

        Result.success(
          entries: entries,
          etag: response.headers["ETag"]?,
          last_modified: response.headers["Last-Modified"]?,
          site_link: "#{base_url}/#{repo}",
          favicon: "#{base_url}/favicon.ico"
        )
      rescue ex
        nil
      end
    end

    private def self.pull_codeberg(info : ProviderInfo, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      base_url = info[:base_url]
      repo = info[:repo]
      error_url = "#{base_url}/#{repo}/releases"

      http_client = Fetcher::H2OHttpClient.new(config)
      request_headers = Fetcher::H2OHttpClient.build_headers(::HTTP::Headers.new)

      result = try_codeberg_api(repo, limit, http_client, request_headers)
      return result if result && result.success?

      result = try_codeberg_releases_atom(repo, limit, http_client, request_headers)
      return result if result

      Fetcher.error_result(ErrorKind::HTTPError, "Codeberg fetch error: No releases found", 404)
    end

    private def self.try_codeberg_api(repo : String, limit : Int32, http_client : H2OHttpClient, headers : ::HTTP::Headers) : Result?
      api_url = "https://codeberg.org/api/v1/repos/#{repo}/releases"

      begin
        response = http_client.get(api_url, headers)

        return nil if response.status_code == 404
        return nil unless (200..299).includes?(response.status_code)

        releases = Array(JSON::Any).from_json(response.body)
        return nil if releases.empty?

        entries = releases.first(limit).map do |release|
          parse_codeberg_release(release, repo)
        end

        Result.success(
          entries: entries,
          etag: response.headers["ETag"]?,
          site_link: "https://codeberg.org/#{repo}",
          favicon: "https://codeberg.org/favicon.ico"
        )
      rescue ex : JSON::ParseException
        nil
      rescue ex
        nil
      end
    end

    private def self.parse_codeberg_release(release : JSON::Any, repo : String) : Entry
      tag = release["tag_name"]?.try(&.as_s) || ""
      name = release["name"]?.try(&.as_s).presence || tag
      html_url = release["html_url"]?.try(&.as_s) || release["url"]?.try(&.as_s) || ""
      published_at = release["published_at"]? || release["created_at"]?
      body = release["body"]?.try(&.as_s) || ""

      pub_date = TimeParser.parse_iso8601(published_at.try(&.as_s))

      Entry.create(
        title: "#{repo} #{name}",
        url: html_url,
        source_type: SourceType::Codeberg,
        content: body,
        content_html: body.presence,
        published_at: pub_date,
        version: tag
      )
    end

    private def self.try_codeberg_releases_atom(repo : String, limit : Int32, http_client : H2OHttpClient, headers : ::HTTP::Headers) : Result?
      atom_url = "https://codeberg.org/#{repo}/releases.atom"

      begin
        response = http_client.get(atom_url, headers)

        return nil if response.status_code == 404
        return nil unless (200..299).includes?(response.status_code)

        entries = parse_atom_entries(response.body, "codeberg", limit)
        return nil if entries.empty?

        Result.success(
          entries: entries,
          etag: response.headers["ETag"]?,
          last_modified: response.headers["Last-Modified"]?,
          site_link: "https://codeberg.org/#{repo}",
          favicon: "https://codeberg.org/favicon.ico"
        )
      rescue ex
        nil
      end
    end

    private def self.parse_atom_entries(body : String, source : String, limit : Int32) : Array(Entry)
      xml = XML.parse(body, options: XML::ParserOptions::RECOVER |
                                     XML::ParserOptions::NOENT |
                                     XML::ParserOptions::NONET)

      xml.xpath_nodes("//entry").first(limit).map do |entry|
        parse_atom_entry(entry, source)
      end
    rescue XML::Error
      [] of Entry
    end

    private def self.parse_atom_entry(entry : XML::Node, source : String) : Entry
      title_node = entry.xpath_node("title")
      title = title_node.nil? ? "Untitled" : Entry.sanitize_title(title_node.text)

      link_node = entry.xpath_node("link")
      link = link_node.try(&.[]?("href")).try(&.strip).presence ||
             link_node.try(&.text).try(&.strip).presence || ""

      published_node = entry.xpath_node("published") || entry.xpath_node("updated")
      pub_date = TimeParser.parse(published_node.try(&.text))

      content_node = entry.xpath_node("content")
      content = content_node.try(&.text).try(&.strip) || ""

      version = extract_version_from_title(title)

      Entry.create(
        title: title,
        url: link,
        source_type: SourceType.from_string(source),
        content: content,
        content_html: content.presence,
        published_at: pub_date,
        version: version
      )
    end

    private def self.extract_version_from_title(title : String) : String?
      match = title.match(/v?\d+\.\d+(?:\.\d+)?(?:[-._]?\w+)?/)
      match ? match[0] : nil
    end
  end
end
