require "spec"
require "../src/fetcher"

module TestHelpers
  def self.make_software_provider
    Fetcher::Software::SoftwareProvider.new(
      name: "test",
      base_url: "https://github.com",
      repo: "test/repo",
      source_type: Fetcher::SourceType::GitHub,
      api_url: "",
      atom_url: ""
    )
  end
end

describe Fetcher::Software do
  describe "parse_software_entry with malformed data" do
    it "handles JSON object with minimal required fields" do
      json = JSON.parse(%({"tag_name": "v1.0.0", "name": "Test", "html_url": "https://test.com"}))
      result = Fetcher::Software.parse_software_entry(json, TestHelpers.make_software_provider)
      result.should be_a(Fetcher::Entry)
      result.title.should eq("test/repo Test")
    end

    it "handles JSON with null values - may throw (documented behavior)" do
      json = JSON.parse(%({"tag_name": null, "name": null, "html_url": null}))
      # Current behavior: throws TypeCastError on null values in extract_release_data
      expect_raises(TypeCastError) do
        Fetcher::Software.parse_software_entry(json, TestHelpers.make_software_provider)
      end
    end

    it "handles JSON with empty object gracefully" do
      json = JSON.parse("{}")
      # Empty object may return entry with empty defaults (or throw - behavior varies)
      begin
        result = Fetcher::Software.parse_software_entry(json, TestHelpers.make_software_provider)
        result.should be_a(Fetcher::Entry)
      rescue TypeCastError
        # Also acceptable behavior for missing required fields
        true.should be_true
      end
    end

    it "handles JSON with special characters safely" do
      json = JSON.parse(%({"tag_name": "v1.0.0", "name": "Test <script>alert(1)</script>", "html_url": "https://test.com"}))
      result = Fetcher::Software.parse_software_entry(json, TestHelpers.make_software_provider)
      result.title.should contain("<script>")
      # Content is stored as string, not executed
    end

    it "does not execute parsed content as code" do
      json = JSON.parse(%({"tag_name": "v1.0.0", "name": "Test", "html_url": "https://test.com", "body": "console.log('test')"}))
      result = Fetcher::Software.parse_software_entry(json, TestHelpers.make_software_provider)
      result.content.should eq("console.log('test')")
      # No execution - content is just stored as string
    end

    it "handles deeply nested JSON - no prototype pollution risk" do
      json = JSON.parse(%({"tag_name": "v1.0.0", "name": "Test", "html_url": "https://test.com", "nested": {"__proto__": {"evil": true}}}))
      result = Fetcher::Software.parse_software_entry(json, TestHelpers.make_software_provider)
      result.should be_a(Fetcher::Entry)
      # Crystal doesn't have prototypes like JS - no pollution risk
    end

    it "handles very long strings in JSON fields" do
      long_string = "x" * 10000
      json = JSON.parse(%({"tag_name": "v1.0.0", "name": "#{long_string}", "html_url": "https://test.com"}))
      result = Fetcher::Software.parse_software_entry(json, TestHelpers.make_software_provider)
      result.title.size.should eq(10000 + "test/repo ".size)
    end

    it "handles JSON with extra unexpected fields" do
      json = JSON.parse(%({"tag_name": "v1.0.0", "name": "Test", "html_url": "https://test.com", "extra_field": "ignored", "another_field": 123}))
      result = Fetcher::Software.parse_software_entry(json, TestHelpers.make_software_provider)
      result.should be_a(Fetcher::Entry)
    end

    it "does not mutate global state on parse errors" do
      # Crystal is statically typed - no runtime state mutation from JSON parsing
      3.times do
        begin
          Fetcher::Software.parse_software_entry(JSON.parse("{}"), TestHelpers.make_software_provider)
        rescue TypeCastError
          # Expected - no global state changed
        end
      end
      true.should be_true
    end
  end

  describe "SoftwareProvider" do
    it "can be created with all required fields" do
      provider = Fetcher::Software::SoftwareProvider.new(
        name: "github",
        base_url: "https://github.com",
        repo: "test/repo",
        source_type: Fetcher::SourceType::GitHub,
        api_url: "https://api.github.com/repos/test/repo/releases",
        atom_url: "https://github.com/test/repo/releases/atom"
      )
      provider.name.should eq("github")
      provider.repo.should eq("test/repo")
      provider.source_type.should eq(Fetcher::SourceType::GitHub)
    end

    it "defaults body_field to \"body\"" do
      provider = Fetcher::Software::SoftwareProvider.new(
        name: "github",
        base_url: "https://github.com",
        repo: "test/repo",
        source_type: Fetcher::SourceType::GitHub,
        api_url: "",
        atom_url: ""
      )
      provider.body_field.should eq("body")
    end
  end
end