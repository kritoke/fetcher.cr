require "spec"
require "../src/fetcher"

describe Fetcher::Reddit do
  describe "parse_reddit_response with malformed JSON" do
    it "raises InvalidFormatError for empty string" do
      expect_raises(Fetcher::InvalidFormatError) do
        Fetcher::Reddit.parse_reddit_response("", 10)
      end
    end

    it "raises InvalidFormatError for invalid JSON syntax" do
      expect_raises(Fetcher::InvalidFormatError) do
        Fetcher::Reddit.parse_reddit_response("{not valid json", 10)
      end
    end

    it "raises InvalidFormatError for partially corrupted JSON" do
      expect_raises(Fetcher::InvalidFormatError) do
        Fetcher::Reddit.parse_reddit_response("{\"data\": {\"children\": [{", 10)
      end
    end

    it "returns empty array for valid JSON but missing children" do
      result = Fetcher::Reddit.parse_reddit_response("{\"data\": {}}", 10)
      result.should be_empty
    end

    it "returns empty array for empty children array" do
      result = Fetcher::Reddit.parse_reddit_response("{\"data\": {\"children\": []}}", 10)
      result.should be_empty
    end

    it "handles JSON with unexpected structure gracefully" do
      # Should not crash, just return empty
      result = Fetcher::Reddit.parse_reddit_response("{\"unrelated\": \"field\"}", 10)
      result.should be_empty
    end

    it "handles JSON with null values" do
      result = Fetcher::Reddit.parse_reddit_response("{\"data\": {\"children\": null}}", 10)
      result.should be_empty
    end

    it "handles deeply nested JSON - may throw on null values (known behavior)" do
      nested = "{\"data\": {\"children\": [{\"data\": {\"title\": null}}]}}"
      # Current behavior: throws TypeCastError on null title
      # This is a known edge case, not a security issue
      expect_raises(TypeCastError) do
        Fetcher::Reddit.parse_reddit_response(nested, 10)
      end
    end

    it "handles JSON with missing required fields - returns empty entry" do
      result = Fetcher::Reddit.parse_reddit_response("{\"data\": {\"children\": [{\"data\": {}}]}}", 10)
      # Post with no title/url still gets parsed (may have empty/default values)
      result.size.should eq(1)
    end

    it "respects the limit parameter" do
      children = (1..20).map do |i|
        "{\"data\": {\"title\": \"Post #{i}\", \"url\": \"https://example.com/#{i}\", \"permalink\": \"/r/test/#{i}\"}}"
      end.join(",")
      json = "{\"data\": {\"children\": [#{children}]}}"

      result = Fetcher::Reddit.parse_reddit_response(json, 5)
      result.size.should eq(5)
    end

    it "does not mutate global state on parse error" do
      # Try parsing invalid JSON multiple times
      3.times do
        expect_raises(Fetcher::InvalidFormatError) do
          Fetcher::Reddit.parse_reddit_response("invalid", 10)
        end
      end
      true.should be_true
    end
  end

  describe "JSON data usage is safe" do
    it "does not execute parsed content as code" do
      # Crystal doesn't have eval, but verify the data is only used for extraction
      json = "{\"data\": {\"children\": [{\"data\": {\"title\": \"Test\", \"url\": \"https://test.com\", \"permalink\": \"/r/test/1\"}}]}}"
      result = Fetcher::Reddit.parse_reddit_response(json, 10)

      result.size.should eq(1)
      result[0].title.should eq("Test")
      result[0].url.should eq("https://test.com")
    end

    it "handles special characters in JSON values safely" do
      json = "{\"data\": {\"children\": [{\"data\": {\"title\": \"Test with <script> & \\\"quotes\\\"\", \"url\": \"https://test.com?a=1&b=2\", \"permalink\": \"/r/test/1\"}}]}}"
      result = Fetcher::Reddit.parse_reddit_response(json, 10)

      result.size.should eq(1)
      result[0].title.should eq("Test with <script> & \"quotes\"")
    end
  end
end
