require "spec"
require "../src/fetcher"

describe Fetcher::URLValidator do
  describe ".valid?" do
    it "accepts regular hostname URLs" do
      Fetcher::URLValidator.valid?("https://news.ycombinator.com/rss").should be_true
    end

    it "accepts hostname URLs with query strings" do
      Fetcher::URLValidator.valid?("http://feeds.feedburner.com/eset/blog?format=xml").should be_true
    end

    it "accepts hostname URLs with paths" do
      Fetcher::URLValidator.valid?("https://arstechnica.com/science/feed/").should be_true
    end

    it "rejects localhost" do
      Fetcher::URLValidator.valid?("http://localhost/feed").should be_false
    end

    it "rejects localhost subdomain" do
      Fetcher::URLValidator.valid?("http://app.localhost/feed").should be_false
    end

    it "rejects 0.0.0.0" do
      Fetcher::URLValidator.valid?("http://0.0.0.0/feed").should be_false
    end

    it "rejects IPv4 loopback" do
      Fetcher::URLValidator.valid?("http://127.0.0.1/feed").should be_false
    end

    it "rejects RFC 1918 private IPs" do
      Fetcher::URLValidator.valid?("http://192.168.1.1/feed").should be_false
      Fetcher::URLValidator.valid?("http://10.0.0.1/feed").should be_false
      Fetcher::URLValidator.valid?("http://172.16.0.1/feed").should be_false
    end

    it "accepts public IPv4 addresses" do
      Fetcher::URLValidator.valid?("http://1.1.1.1/feed").should be_true
      Fetcher::URLValidator.valid?("http://8.8.8.8/feed").should be_true
    end

    it "rejects nil URL" do
      Fetcher::URLValidator.valid?(nil).should be_false
    end

    it "rejects empty URL" do
      Fetcher::URLValidator.valid?("").should be_false
    end

    it "rejects overly long URL" do
      long_url = "https://example.com/" + ("a" * 2029)
      Fetcher::URLValidator.valid?(long_url).should be_false
    end

    it "accepts URL at max length" do
      padding = 2048 - "https://example.com/".size
      Fetcher::URLValidator.valid?("https://example.com/" + ("a" * padding)).should be_true
    end

    it "rejects non-http schemes" do
      Fetcher::URLValidator.valid?("ftp://example.com/feed").should be_false
      Fetcher::URLValidator.valid?("file:///etc/passwd").should be_false
    end
  end

  describe ".resolve_and_validate" do
    it "allows hostnames without DNS lookup" do
      Fetcher::URLValidator.resolve_and_validate("https://news.ycombinator.com/rss").should be_true
    end

    it "allows hostname URLs with query strings" do
      Fetcher::URLValidator.resolve_and_validate("http://feeds.feedburner.com/eset/blog?format=xml").should be_true
    end

    it "rejects private IPv4 addresses via DNS" do
      Fetcher::URLValidator.resolve_and_validate("http://192.168.1.1/feed").should be_false
      Fetcher::URLValidator.resolve_and_validate("http://10.0.0.1/feed").should be_false
    end

    it "allows public IPv4 addresses via DNS" do
      Fetcher::URLValidator.resolve_and_validate("http://1.1.1.1/feed").should be_true
    end

    it "allows hostnames even when DNS fails" do
      Fetcher::URLValidator.resolve_and_validate("https://nonexistent-domain-12345.example.com/feed").should be_true
    end
  end

  describe ".safe_url" do
    it "returns original URL for valid URLs" do
      Fetcher::URLValidator.safe_url("https://example.com/feed").should eq "https://example.com/feed"
    end

    it "returns '#' for invalid URLs" do
      Fetcher::URLValidator.safe_url("http://localhost/feed").should eq "#"
    end
  end
end
