module Fetcher
  module TimeParser
    RSS_FORMATS = [
      "%a, %d %b %Y %H:%M:%S %z",
      "%Y-%m-%dT%H:%M:%S%z",
      "%Y-%m-%dT%H:%M:%SZ",
      "%Y-%m-%dT%H:%M:%S",
      "%Y-%m-%d",
    ]

    ATOM_FORMATS = [
      "%Y-%m-%dT%H:%M:%S%z",
      "%Y-%m-%dT%H:%M:%SZ",
      "%Y-%m-%dT%H:%M:%S",
      "%Y-%m-%d",
    ]

    def self.parse(time_str : String?, formats : Array(String)? = nil) : Time?
      return unless time_str
      stripped = time_str.strip
      return if stripped.empty?

      format_list = formats || RSS_FORMATS

      format_list.each do |fmt|
        begin
          return Time.parse(stripped, fmt, Time::Location::UTC)
        rescue
        end
      end

      begin
        Time.parse_iso8601(stripped)
      rescue
        nil
      end
    end

    def self.parse_iso8601(time_str : String?) : Time?
      return unless time_str
      stripped = time_str.strip
      return if stripped.empty?

      begin
        Time.parse_iso8601(stripped)
      rescue
        nil
      end
    end
  end
end
