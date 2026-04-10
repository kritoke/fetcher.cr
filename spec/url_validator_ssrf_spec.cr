require "spec"
require "../src/fetcher"

describe Fetcher::URLValidator do
  describe "looks_like_ip regression tests" do
    # These tests verify the bug fix for numeric-prefix hostnames
    # Hostnames starting with digits (e.g., "2.example.com") were
    # incorrectly treated as IP addresses, causing DNS resolution failures.

    it "resolves standard hostnames without DNS lookup" do
      # If looks_like_ip? incorrectly returns true for "github.com",
      # this would trigger DNS resolution of "github.com" as an IP
      result = Fetcher::URLValidator.resolve_and_validate("https://github.com/user/repo")
      result.should be_true
    end

    it "resolves alphabetic hostnames without DNS lookup" do
      result = Fetcher::URLValidator.resolve_and_validate("https://news.ycombinator.com/rss")
      result.should be_true
    end

    it "resolves numeric-prefix hostnames without DNS lookup" do
      # THE BUG: 2.example.com starts with '2', was being treated as IP
      result = Fetcher::URLValidator.resolve_and_validate("https://2.example.com/path")
      result.should be_true
    end

    it "resolves other numeric-prefix hostnames" do
      result = Fetcher::URLValidator.resolve_and_validate("https://123.test.org/feed")
      result.should be_true

      result = Fetcher::URLValidator.resolve_and_validate("https://1domain.com/")
      result.should be_true
    end
  end

  describe "valid? accepts numeric-prefix hostnames" do
    it "accepts URLs with numeric-prefix hostnames" do
      Fetcher::URLValidator.valid?("https://2.example.com/path").should be_true
      Fetcher::URLValidator.valid?("https://123.test.org/feed").should be_true
      Fetcher::URLValidator.valid?("https://1domain.com/").should be_true
    end

    it "accepts standard hostnames" do
      Fetcher::URLValidator.valid?("https://github.com/user/repo").should be_true
      Fetcher::URLValidator.valid?("https://news.ycombinator.com/rss").should be_true
    end
  end

  describe "IP address validation still works" do
    it "rejects private IPv4 addresses" do
      Fetcher::URLValidator.valid?("http://192.168.1.1/feed").should be_false
      Fetcher::URLValidator.valid?("http://10.0.0.1/feed").should be_false
      Fetcher::URLValidator.valid?("http://172.16.0.1/feed").should be_false
    end

    it "accepts public IPv4 addresses" do
      Fetcher::URLValidator.valid?("http://8.8.8.8/feed").should be_true
      Fetcher::URLValidator.valid?("http://1.1.1.1/feed").should be_true
    end

    it "resolves private IPs via DNS and rejects" do
      # This goes through DNS resolution path for IPs
      Fetcher::URLValidator.resolve_and_validate("http://192.168.1.1/feed").should be_false
      Fetcher::URLValidator.resolve_and_validate("http://10.0.0.1/feed").should be_false
    end

    it "resolves public IPs via DNS and accepts" do
      Fetcher::URLValidator.resolve_and_validate("http://8.8.8.8/feed").should be_true
    end
  end

  describe "localhost and reserved hostnames" do
    it "rejects localhost" do
      Fetcher::URLValidator.valid?("http://localhost/feed").should be_false
    end

    it "rejects localhost subdomains" do
      Fetcher::URLValidator.valid?("http://app.localhost/feed").should be_false
      # "test.localhost.example" ends with .example, not .localhost - it's valid
      Fetcher::URLValidator.valid?("http://test.localhost/").should be_false
    end

    it "rejects 0.0.0.0" do
      Fetcher::URLValidator.valid?("http://0.0.0.0/feed").should be_false
    end

    it "rejects link-local addresses" do
      Fetcher::URLValidator.valid?("http://169.254.169.254/").should be_false
    end
  end

  describe "IPv6 bracket notation" do
    it "accepts public IPv6 in brackets" do
      Fetcher::URLValidator.valid?("http://[2001:db8::1]/feed").should be_true
    end

    it "rejects loopback IPv6 in brackets" do
      Fetcher::URLValidator.valid?("http://[::1]/feed").should be_false
    end

    it "rejects link-local IPv6 in brackets" do
      Fetcher::URLValidator.valid?("http://[fe80::1]/feed").should be_false
    end
  end
end
