require "json"
require "../link_resolver"
require "../error_handler"

module Fetcher
  module Software
    module Codeberg
      def self.pull_releases(provider : SoftwareProvider, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
        http_client = Fetcher::CrestHttpClient.new(config)
        response = http_client.get(provider.api_url, build_codeberg_headers(config))

        case response.status_code
        when 200..299 then handle_success_response(response, provider, limit)
        when 304      then handle_not_modified(response)
        when 429      then handle_rate_limited(provider.api_url)
        when 500..599 then handle_server_error(response.status_code, provider.api_url)
        else               handle_http_error(response.status_code, provider.api_url)
        end
      end

      private def self.build_codeberg_headers(config : RequestConfig) : ::HTTP::Headers
        codeberg_headers = ::HTTP::Headers.new
        codeberg_headers["Accept"] = "application/json"
        codeberg_headers["Authorization"] = "Bearer #{config.codeberg_token}" if config.codeberg_token
        Fetcher::CrestHttpClient.build_headers(codeberg_headers)
      end

      private def self.handle_success_response(response : ::HTTP::Client::Response, provider : SoftwareProvider, limit : Int32) : Result
        result = parse_json_response(response.body, provider.api_url)
        return result if result.is_a?(Result)

        releases = result.as(Array(JSON::Any))
        stable_releases = releases.reject { |release| release["prerelease"]?.try(&.as_bool) || false }

        entries = stable_releases.first(limit).map { |release| parse_entry(release, provider) }
        Result.builder
          .entries(entries)
          .etag(response.headers["ETag"]?)
          .last_modified(response.headers["Last-Modified"]?)
          .site_link("#{provider.base_url}/#{provider.repo}")
          .favicon("#{provider.base_url}/favicon.ico")
          .build
      end

      private def self.handle_not_modified(response : ::HTTP::Client::Response) : Result
        Result.success(
          entries: [] of Entry,
          etag: response.headers["ETag"]?,
          last_modified: response.headers["Last-Modified"]?
        )
      end

      private def self.handle_rate_limited(url : String) : Result
        Result.error(Error.rate_limited("Rate limited", url))
      end

      private def self.handle_server_error(status : Int32, url : String) : Result
        Result.error(Error.server_error(status, "Server error: #{status}", url))
      end

      private def self.handle_http_error(status : Int32, url : String) : Result
        Result.error(Error.http(status, "HTTP #{status}", url))
      end

      # Parse JSON response and handle error responses from Codeberg API
      private def self.parse_json_response(body : String, url : String) : Array(JSON::Any) | Result
        # First check if it looks like an array
        stripped = body.lstrip
        unless stripped.starts_with?('[')
          # Likely an error response - extract the error message if possible
          error_msg = extract_error_message(body)
          if error_msg
            error = Error.invalid_format("Codeberg API error: #{error_msg}", url)
            return Result.error(error)
          else
            error = Error.invalid_format("Expected JSON array, got #{stripped[0..Math.min(50, stripped.size - 1)]?}", url)
            return Result.error(error)
          end
        end

        begin
          Array(JSON::Any).from_json(body)
        rescue ex : JSON::ParseException
          error = Error.invalid_format("Invalid JSON from #{url}: #{ex.message}", url)
          Result.error(error)
        end
      end

      # Extract error message from Codeberg API error responses
      private def self.extract_error_message(body : String) : String?
        parsed = JSON.parse(body)
        # Check if it's a JSON object (hash)
        obj = parsed.as_h?
        return unless obj

        # Try common error message fields
        parsed["message"]?.try(&.as_s) ||
          parsed["error"]?.try(&.as_s) ||
          extract_first_error(parsed["errors"]) ||
          parsed["error_description"]?.try(&.as_s)
      rescue
        nil
      end

      # Helper to extract error from "errors" array field
      private def self.extract_first_error(errors_field : JSON::Any?) : String?
        return unless errors_field
        errors = errors_field.as_a?
        return if errors.nil? || errors.empty?
        errors.first?.try(&.as_s)
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

      private def self.extract_release_data(release : JSON::Any, provider : SoftwareProvider) : CodebergReleaseData
        tag = release["tag_name"]?.try(&.as_s) || ""
        name = release["name"]?.try(&.as_s).presence || tag
        body = release[provider.body_field]?.try(&.as_s) || ""
        html_url = release["html_url"]?.try(&.as_s) || release["url"]?.try(&.as_s) || ""

        CodebergReleaseData.new(
          tag: tag,
          name: name,
          body: body,
          html_url: html_url,
          pub_date: parse_release_date(release),
          link_data: LinkResolver.resolve_from_url(html_url)
        )
      end

      private def self.parse_release_date(release : JSON::Any) : Time?
        published_at = release["published_at"]? || release["created_at"]?
        TimeParser.parse(published_at.try(&.as_s))
      end

      record CodebergReleaseData,
        tag : String,
        name : String,
        body : String,
        html_url : String,
        pub_date : Time?,
        link_data : LinkResolver::LinkData
    end
  end
end
