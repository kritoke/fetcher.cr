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
  end
end
