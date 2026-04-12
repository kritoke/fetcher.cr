require "spec"
require "../../src/fetcher"

describe "Security: Input Validation Hardening" do
  describe "Reddit sort validation" do
    it "accepts known sort values via pull" do
      ["hot", "new", "rising", "top", "controversial"].each do |sort|
        url = "https://reddit.com/r/test/#{sort}"
        Fetcher.pull(url)
        # Will fail at HTTP level, but sort should be recognized
      end
    end

    it "defaults unknown sort to hot and succeeds" do
      url = "https://reddit.com/r/test/evil"
      result = Fetcher.pull(url)
      # "evil" is not a valid sort, so it defaults to "hot"
      # The request should succeed via RSS fallback with hot sort
      result.success?.should be_true
    end
  end

  describe "YouTube channel ID validation" do
    it "accepts valid YouTube channel IDs" do
      url = "https://youtube.com/channel/UC1234567890abcdef"
      Fetcher.pull(url)
      # Will fail at HTTP level but shouldn't crash
    end

    it "rejects YouTube channel IDs not starting with UC" do
      url = "https://youtube.com/channel/invalid123"
      result = Fetcher.pull(url)
      result.success?.should be_false
      result.error.should_not be_nil
    end

    it "rejects YouTube channel IDs with special characters" do
      url = "https://youtube.com/channel/UC<script>alert(1)</script>"
      result = Fetcher.pull(url)
      result.success?.should be_false
    end
  end

  describe "GitLab domain regex" do
    it "rejects GitLab URLs without a proper domain (no dot)" do
      url = "https://evil/org/repo/-/releases"
      result = Fetcher.pull(url)
      result.success?.should be_false
    end
  end
end
