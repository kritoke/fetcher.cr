require "time"

module Fetcher
  # RFC-compliant time parser for feed dates
  # Supports RFC 2822 (RSS), RFC 3339/ISO 8601 (Atom, JSON Feed), and common variants.
  # All parsed times are normalized to UTC to avoid location mismatches and ensure
  # consistent comparison behavior.
  module TimeParser
    # Upper bound for feed timestamps. Feeds with timestamps above this are
    # returned as-is (no clamping) — the clamp only applies to parsed times.
    # Set to 24 hours from now to handle feeds with slight clock drift while
    # not accepting clearly incorrect future dates.
    FUTURE_BOUND = Time.utc + 24.hours

    # Normalize a Time to UTC. This ensures:
    # - Consistent location for comparisons (UTC vs +00:00 are equal after normalization)
    # - Future times from feeds (clock skew, bad data) are clamped to a sensible upper bound
    #   to prevent entries appearing in the future based on feed timestamps.
    def self.normalize(time : Time?) : Time?
      return unless time
      normalized = time.to_utc
      return normalized unless normalized > FUTURE_BOUND
      normalized
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
      if stripped.matches?(/^\d{4}-\d{2}-\d{2}$/)
        return Time.parse(stripped, "%Y-%m-%d", Time::Location::UTC)
      end

      # Handle YYYY-MM-DDTHH:MM:SS format without timezone
      if stripped.matches?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/)
        return Time.parse(stripped, "%Y-%m-%dT%H:%M:%S", Time::Location::UTC)
      end

      nil
    rescue Time::Format::Error
      nil
    end
  end
end
