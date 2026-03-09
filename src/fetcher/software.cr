require "json"
require "xml"
require "./entry"
require "./result"
require "./retry"
require "./http_client_v2"
require "./time_parser"
require "./exceptions"

module Fetcher
  module Software
    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      provider = detect_provider(url)
      return Fetcher.error_result(ErrorKind::InvalidURL, "Unknown software provider") unless provider

      Fetcher.with_retry(config) do
        case provider
        when "github"
          pull_github(url, headers, limit, config)
        when "gitlab"
          pull_gitlab(url, headers, limit, config)
        when "codeberg"
          pull_codeberg(url, headers, limit, config)
        else
          Fetcher.error_result(ErrorKind::InvalidURL, "Unsupported provider")
        end
      end
    end

    private def self.detect_provider(url : String) : String?
      return "github" if url.includes?("github.com") && url.includes?("/releases")
      return "gitlab" if url.includes?("gitlab.com") && url.includes?("/-/releases")
      return "codeberg" if url.includes?("codeberg.org") && url.includes?("/releases")
      nil
    end

    private def self.pull_github(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      repo = extract_github_repo(url)
      error_url = url
      return Fetcher.error_result(ErrorKind::InvalidURL, "Invalid GitHub repo URL", nil) unless repo

      api_url = "https://api.github.com/repos/#{repo}/releases"

      github_headers = ::HTTP::Headers.new
      github_headers["Accept"] = "application/vnd.github.v3+json"
      merged = Fetcher::HttpClient.build_headers(github_headers)

      http_client = Fetcher::HttpClient.new(config)
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
    rescue ex : HttpClient::DNSError
      error = Error.dns("DNS error: #{ex.message}", error_url)
      raise DNSError.new(error.message, error)
    rescue ex : FetchError
      # Re-raise typed exceptions
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

      pub_date = TimeParser.parse_iso8601(published)

      Entry.create(title: "#{repo} #{name}", url: html_url, source_type: SourceType::GitHub, published_at: pub_date, version: tag)
    end

    private def self.extract_github_repo(url : String) : String?
      match = url.match(%r{github\.com/([^/]+/[^/]+)/?})
      match ? match[1] : nil
    end

    private def self.pull_gitlab(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      repo = extract_gitlab_repo(url)
      error_url = url
      return Fetcher.error_result(ErrorKind::InvalidURL, "Invalid GitLab repo URL") unless repo

      atom_url = "https://gitlab.com/#{repo}/-/releases.atom"

      http_client = Fetcher::HttpClient.new(config)
      response = http_client.get(atom_url, Fetcher::HttpClient.build_headers(::HTTP::Headers.new))

      if response.status_code == 429
        error = Error.rate_limited("GitLab rate limited", atom_url)
        raise RateLimitError.new(error.message, error)
      end

      return Fetcher.error_result(ErrorKind::HTTPError, "GitLab fetch error: #{response.status_code}", response.status_code) unless (200..299).includes?(response.status_code)

      entries = parse_atom_entries(response.body, "gitlab", limit)

      Result.success(
        entries: entries,
        etag: response.headers["ETag"]?,
        last_modified: response.headers["Last-Modified"]?,
        site_link: "https://gitlab.com/#{repo}",
        favicon: "https://gitlab.com/favicon.ico"
      )
    rescue ex : IO::TimeoutError
      error = Error.timeout("Timeout: #{ex.message}", error_url)
      raise TimeoutError.new(error.message, error)
    rescue ex : HttpClient::DNSError
      error = Error.dns("DNS error: #{ex.message}", error_url)
      raise DNSError.new(error.message, error)
    rescue ex : XML::Error
      error = Error.invalid_format("XML parsing error: #{ex.message}", error_url)
      raise InvalidFormatError.new(error.message, error)
    rescue ex : FetchError
      # Re-raise typed exceptions
      raise ex
    rescue ex
      if Fetcher.transient_error?(ex)
        error = Error.unknown(ex.message || "Unknown error", error_url)
        raise UnknownError.new(error.message, error)
      end
      error = Error.unknown("#{ex.class}: #{ex.message}", error_url)
      Fetcher.error_result(error)
    end

    private def self.extract_gitlab_repo(url : String) : String?
      match = url.match(%r{gitlab\.com/([^/]+/[^/]+)})
      match ? match[1] : nil
    end

    private def self.pull_codeberg(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      repo = extract_codeberg_repo(url)
      error_url = url
      return Fetcher.error_result(ErrorKind::InvalidURL, "Invalid Codeberg repo URL") unless repo

      atom_url = "https://codeberg.org/#{repo}/releases.atom"

      http_client = Fetcher::HttpClient.new(config)
      response = http_client.get(atom_url, Fetcher::HttpClient.build_headers(::HTTP::Headers.new))

      if response.status_code == 429
        error = Error.rate_limited("Codeberg rate limited", atom_url)
        raise RateLimitError.new(error.message, error)
      end

      return Fetcher.error_result(ErrorKind::HTTPError, "Codeberg fetch error: #{response.status_code}", response.status_code) unless (200..299).includes?(response.status_code)

      entries = parse_atom_entries(response.body, "codeberg", limit)

      Result.success(
        entries: entries,
        etag: response.headers["ETag"]?,
        last_modified: response.headers["Last-Modified"]?,
        site_link: "https://codeberg.org/#{repo}",
        favicon: "https://codeberg.org/favicon.ico"
      )
    rescue ex : IO::TimeoutError
      error = Error.timeout("Timeout: #{ex.message}", error_url)
      raise TimeoutError.new(error.message, error)
    rescue ex : HttpClient::DNSError
      error = Error.dns("DNS error: #{ex.message}", error_url)
      raise DNSError.new(error.message, error)
    rescue ex : XML::Error
      error = Error.invalid_format("XML parsing error: #{ex.message}", error_url)
      raise InvalidFormatError.new(error.message, error)
    rescue ex : FetchError
      # Re-raise typed exceptions
      raise ex
    rescue ex
      if Fetcher.transient_error?(ex)
        error = Error.unknown(ex.message || "Unknown error", error_url)
        raise UnknownError.new(error.message, error)
      end
      error = Error.unknown("#{ex.class}: #{ex.message}", error_url)
      Fetcher.error_result(error)
    end

    private def self.extract_codeberg_repo(url : String) : String?
      match = url.match(%r{codeberg\.org/([^/]+/[^/]+)})
      match ? match[1] : nil
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

      Entry.create(title: title, url: link, source_type: SourceType.from_string(source), published_at: pub_date)
    end
  end
end
