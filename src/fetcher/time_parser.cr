require "time"

module Fetcher
  # RFC-compliant time parser for feed dates
  # Supports RFC 2822 (RSS), RFC 3339/ISO 8601 (Atom, JSON Feed), and common variants
  module TimeParser
    # Parse time from various feed date formats
    def self.parse(time_str : String?) : Time?
      return if time_str.nil? || time_str.empty?

      stripped = time_str.strip
      return if stripped.empty?

      # Try RFC 2822 first (RSS format)
      begin
        return Time.parse_rfc2822(stripped)
      rescue Time::Format::Error
        # Continue to other formats
      end

      # Try ISO 8601 / RFC 3339 (Atom, JSON Feed format)
      begin
        return Time.parse_iso8601(stripped)
      rescue Time::Format::Error
        # Continue to fallback parsing
      end

      # Fallback: try common date-only formats
      begin
        # Handle YYYY-MM-DD format
        if stripped.matches?(/^\d{4}-\d{2}-\d{2}$/)
          return Time.parse(stripped, "%Y-%m-%d", Time::Location::UTC)
        end

        # Handle YYYY-MM-DDTHH:MM:SS format without timezone
        if stripped.matches?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/)
          return Time.parse(stripped, "%Y-%m-%dT%H:%M:%S", Time::Location::UTC)
        end
      rescue
        # Ignore parsing errors in fallback
      end

      nil
    end

    # Parse ISO 8601 date string (for JSON Feed)
    def self.parse_iso8601(time_str : String?) : Time?
      parse(time_str) # Delegate to main parse method which handles ISO 8601
    end

    # Parse RFC 2822 date string (for RSS)
    def self.parse_rfc2822(time_str : String?) : Time?
      parse(time_str) # Delegate to main parse method which handles RFC 2822
    end
  end
end
