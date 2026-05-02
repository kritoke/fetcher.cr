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

        # Handle HTTP errors first
        case response.status_code
        when 200..299
          # Success - now validate we got an array, not an error response
          result = parse_json_response(response.body, provider.api_url)
          if result.is_a?(Result)
            # Non-success result from JSON parsing (invalid JSON or error response)
            # Return this error to let caller handle fallback
            return result
          end

          releases = result.as(Array(JSON::Any))
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
        when 304
          Result.success(
            entries: [] of Entry,
            etag: response.headers["ETag"]?,
            last_modified: response.headers["Last-Modified"]?
          )
        when 429
          error = Error.rate_limited("Rate limited", provider.api_url)
          Result.error(error)
        when 500..599
          error = Error.server_error(response.status_code, "Server error: #{response.status_code}", provider.api_url)
          Result.error(error)
        else
          error = Error.http(response.status_code, "HTTP #{response.status_code}", provider.api_url)
          Result.error(error)
        end
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
