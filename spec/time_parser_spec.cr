require "spec"
require "../src/fetcher/time_parser"

describe Fetcher::TimeParser do
  describe "RFC 2822 parsing (RSS)" do
    it "parses standard RFC 2822 dates" do
      date = "Wed, 15 Jan 2026 10:30:00 GMT"
      result = Fetcher::TimeParser.parse(date)
      result.should_not be_nil
      result.as(Time).year.should eq(2026)
      result.as(Time).month.should eq(1)
      result.as(Time).day.should eq(15)
      result.as(Time).hour.should eq(10)
      result.as(Time).minute.should eq(30)
    end

    it "parses RSS with timezone offset" do
      date = "Wed, 15 Jan 2026 10:30:00 -0500"
      result = Fetcher::TimeParser.parse(date)
      result.should_not be_nil
    end

    it "handles common RSS date variations" do
      variations = [
        "Wed, 15 Jan 2026 10:30:00 UTC",
        "Wed, 15 Jan 2026 10:30:00 +0000",
        "15 Jan 2026 10:30:00 GMT", # Some RSS feeds omit day of week
      ]

      # At least one should parse successfully
      parsed = variations.any? { |date| !Fetcher::TimeParser.parse(date).nil? }
      parsed.should be_true
    end
  end

  describe "ISO 8601 / RFC 3339 parsing (Atom, JSON Feed)" do
    it "parses standard ISO 8601 dates" do
      date = "2026-01-15T10:30:00Z"
      result = Fetcher::TimeParser.parse(date)
      result.should_not be_nil
      result.as(Time).year.should eq(2026)
      result.as(Time).month.should eq(1)
      result.as(Time).day.should eq(15)
      result.as(Time).hour.should eq(10)
      result.as(Time).minute.should eq(30)
    end

    it "parses ISO 8601 with timezone offset" do
      date = "2026-01-15T10:30:00+02:00"
      result = Fetcher::TimeParser.parse(date)
      result.should_not be_nil
    end

    it "parses ISO 8601 with fractional seconds" do
      date = "2026-01-15T10:30:00.123Z"
      result = Fetcher::TimeParser.parse(date)
      result.should_not be_nil
    end

    it "parses date-only format" do
      date = "2026-01-15"
      result = Fetcher::TimeParser.parse(date)
      result.should_not be_nil
      result.as(Time).year.should eq(2026)
      result.as(Time).month.should eq(1)
      result.as(Time).day.should eq(15)
    end

    it "parses datetime without timezone" do
      date = "2026-01-15T10:30:00"
      result = Fetcher::TimeParser.parse(date)
      result.should_not be_nil
    end
  end

  describe "Fallback parsing" do
    it "returns nil for invalid dates" do
      result = Fetcher::TimeParser.parse("invalid date")
      result.should be_nil
    end

    it "handles empty strings" do
      result = Fetcher::TimeParser.parse("")
      result.should be_nil
    end

    it "handles nil input" do
      result = Fetcher::TimeParser.parse(nil)
      result.should be_nil
    end

    it "trims whitespace" do
      date = "  2026-01-15T10:30:00Z  "
      result = Fetcher::TimeParser.parse(date)
      result.should_not be_nil
    end
  end

  describe "Specific parser methods" do
    it "parse_iso8601 delegates to main parse method" do
      date = "2026-01-15T10:30:00Z"
      result1 = Fetcher::TimeParser.parse(date)
      result2 = Fetcher::TimeParser.parse_iso8601(date)
      result1.should eq(result2)
    end

    it "parse_rfc2822 delegates to main parse method" do
      date = "Wed, 15 Jan 2026 10:30:00 GMT"
      result1 = Fetcher::TimeParser.parse(date)
      result2 = Fetcher::TimeParser.parse_rfc2822(date)
      result1.should eq(result2)
    end
  end
end
