module Fetcher
  module Software
    # Shared helpers for parsing software release data from JSON API responses
    module ReleaseHelpers
      # Extract tag name from a release object
      def self.extract_tag(release : JSON::Any) : String
        release["tag_name"]?.try(&.as_s) || ""
      end

      # Extract name, falling back to tag if name is absent
      def self.extract_name(release : JSON::Any) : String
        release["name"]?.try(&.as_s).presence || extract_tag(release)
      end

      # Extract HTML URL from a release object
      # Handles different API formats (GitHub, GitLab, Codeberg)
      def self.extract_html_url(release : JSON::Any) : String
        release["html_url"]?.try(&.as_s) || release["url"]?.try(&.as_s) || ""
      end

      # Parse the published date from a release object
      # Checks multiple possible field names in order of preference
      def self.parse_release_date(release : JSON::Any) : Time?
        published_at = release["published_at"]? ||
                       release["released_at"]? ||
                       release["created_at"]
        TimeParser.normalize(TimeParser.parse(published_at.try(&.as_s)))
      end

      # Check if a release is a prerelease/draft
      def self.prerelease?(release : JSON::Any) : Bool
        release["prerelease"]?.try(&.as_bool) || release["draft"]?.try(&.as_bool) || false
      end
    end
  end
end
