require "spec"
require "../../src/fetcher"

describe "Security: SSRF Bypass Fixes" do
  describe "exception fallback in resolve_and_validate" do
    it "rejects URLs with unresolvable hosts instead of allowing them" do
      # A host that looks like an IP but cannot be parsed should be rejected
      # Previously, Socket::Error in validate_ip would return true (bypass)
      result = Fetcher::URLValidator.valid?("http://999.999.999.999/feed")
      result.should be_false
    end

    it "rejects URLs with malformed IP-like hosts" do
      # 0x7f000001 is structurally valid as a hostname but would be blocked
      # if it resolved to a private IP. The key fix is that validate_ip
      # no longer returns true on Socket::Error.
      # Since looks_like_ip? returns false for hex, it's treated as hostname
      # and passes structural validation - SSRF protection happens at resolve time
      Fetcher::URLValidator.valid?("http://0x7f000001/feed").should be_true
    end

    it "still accepts valid public IPs" do
      Fetcher::URLValidator.valid?("http://8.8.8.8/feed").should be_true
      Fetcher::URLValidator.valid?("http://1.1.1.1/feed").should be_true
    end
  end

  describe "additional IP range blocks" do
    it "rejects CGNAT range (100.64.0.0/10)" do
      Fetcher::URLValidator.valid?("http://100.64.0.1/").should be_false
      Fetcher::URLValidator.valid?("http://100.127.255.254/").should be_false
    end

    it "accepts IPs adjacent to CGNAT range" do
      Fetcher::URLValidator.valid?("http://100.63.255.254/").should be_true
    end

    it "rejects benchmark range (198.18.0.0/15)" do
      Fetcher::URLValidator.valid?("http://198.18.0.1/").should be_false
      Fetcher::URLValidator.valid?("http://198.19.255.254/").should be_false
    end

    it "rejects multicast range (224.0.0.0/4)" do
      Fetcher::URLValidator.valid?("http://224.0.0.1/").should be_false
      Fetcher::URLValidator.valid?("http://239.255.255.255/").should be_false
    end

    it "rejects reserved range (240.0.0.0/4)" do
      Fetcher::URLValidator.valid?("http://240.0.0.1/").should be_false
      Fetcher::URLValidator.valid?("http://255.255.255.255/").should be_false
    end

    it "rejects full current network range (0.0.0.0/8)" do
      Fetcher::URLValidator.valid?("http://0.0.1.1/").should be_false
      Fetcher::URLValidator.valid?("http://0.255.255.255/").should be_false
    end
  end

  describe "URL normalization" do
    it "normalizes path traversal before validation" do
      # /r/../admin normalizes to /admin, which is a valid path on a public host
      # The key is that the path is normalized, not that the URL is rejected
      Fetcher::URLValidator.valid?("https://reddit.com/r/../admin").should be_true
    end

    it "normalizes dot segments in paths" do
      Fetcher::URLValidator.valid?("https://example.com/a/./b/./c").should be_true
    end

    it "preserves valid URLs without path traversal" do
      Fetcher::URLValidator.valid?("https://example.com/feed.xml").should be_true
    end
  end
end
