require "time"

module Fetcher
  # RFC-compliant time parser for feed dates
  # Supports RFC 2822 (RSS), RFC 3339/ISO 8601 (Atom, JSON Feed), and common variants.
  # All parsed times are normalized to UTC to avoid location mismatches and ensure
  # consistent comparison behavior.
  module TimeParser
    # Pre-compiled regexes to avoid repeated compilation in hot path
    FALLBACK_DATE_PATTERN     = /\d{4}-\d{2}-\d{2}$/
    FALLBACK_DATETIME_PATTERN = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/

    # Normalize a Time to UTC. This ensures consistent location for comparisons
    # (UTC vs +00:00 are equal after normalization).
    def self.normalize(time : Time?) : Time?
      return unless time
      time.to_utc
    end

    # Parse time from various feed date formats, returning UTC-normalized Time.
    def self.parse(time_str : String?) : Time?
      return if time_str.nil? || time_str.empty?

      stripped = time_str.strip
      return if stripped.empty?

      parse_rfc2822(stripped) ||
        parse_iso8601(stripped) ||
        parse_fallback(stripped)
    rescue Time::Format::Error
      nil
    end

    private def self.parse_rfc2822(stripped : String) : Time?
      Time.parse_rfc2822(stripped)
    rescue Time::Format::Error
      nil
    end

    private def self.parse_iso8601(stripped : String) : Time?
      Time.parse_iso8601(stripped)
    rescue Time::Format::Error
      nil
    end

    private def self.parse_fallback(stripped : String) : Time?
      # Handle YYYY-MM-DD format
      if stripped.matches?(FALLBACK_DATE_PATTERN)
        return Time.parse(stripped, "%Y-%m-%d", Time::Location::UTC)
      end

      # Handle YYYY-MM-DDTHH:MM:SS format without timezone
      if stripped.matches?(FALLBACK_DATETIME_PATTERN)
        return Time.parse(stripped, "%Y-%m-%dT%H:%M:%S", Time::Location::UTC)
      end

      nil
    rescue Time::Format::Error
      nil
    end
  end
end
