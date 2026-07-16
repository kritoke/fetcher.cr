require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"
require "uri"

module Fetcher
  # Mock validator that tracks calls for verification
  class TrackingMockValidator < URLValidator::Service
    property valid = true
    property resolvable = true
    property connected_ip_ok = true
    getter resolve_calls = [] of String

    def valid?(url : String?) : Bool
      @valid
    end

    def resolve_and_validate(url : String) : Bool
      @resolve_calls << url
      @resolvable
    end

    def validate_connected_ip(host : String, connected_ip : Socket::IPAddress) : Bool
      @connected_ip_ok
    end

    def extract_domain(url : String) : String
      begin
        URI.parse(url).host || "default"
      rescue
        "default"
      end
    end

    def looks_like_ip?(host : String) : Bool
      host.size > 0 && host[0].ascii_number?
    end

    def validate_ip(host : String) : Bool
      !host.starts_with?("10.")
    end

    def register_ip(host : String, ip : Socket::IPAddress) : Nil
      # no-op
    end

    def reset : Nil
      @resolve_calls.clear
    end
  end
end

describe Fetcher::CrestHttpClient do
  describe "check_ssrf" do
    it "passes when validator says URL is valid and resolvable" do
      cfg = Fetcher::RequestConfig.new
      mock = Fetcher::TrackingMockValidator.new
      mock.valid = true
      mock.resolvable = true
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      client.debug_check_ssrf("https://example.com/feed")
      mock.resolve_calls.should contain("https://example.com/feed")
    end

    it "raises DNSError when validator says URL is invalid" do
      cfg = Fetcher::RequestConfig.new
      mock = Fetcher::TrackingMockValidator.new
      mock.valid = false
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      expect_raises(Fetcher::DNSError) do
        client.debug_check_ssrf("https://blocked.example.com/")
      end
    end

    it "raises DNSError when validator says URL is not resolvable (SSRF detected)" do
      cfg = Fetcher::RequestConfig.new
      mock = Fetcher::TrackingMockValidator.new
      mock.valid = true
      mock.resolvable = false
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      expect_raises(Fetcher::DNSError) do
        client.debug_check_ssrf("https://ssrf.example.com/")
      end
    end

    it "tracks resolve_and_validate calls" do
      cfg = Fetcher::RequestConfig.new
      mock = Fetcher::TrackingMockValidator.new
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      client.debug_check_ssrf("https://test1.example.com/")
      client.debug_check_ssrf("https://test2.example.com/")

      mock.resolve_calls.size.should eq(2)
    end
  end

  describe "validate_redirect_target" do
    it "passes when validator returns true for both checks" do
      cfg = Fetcher::RequestConfig.new
      mock = Fetcher::TrackingMockValidator.new
      mock.valid = true
      mock.resolvable = true
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      client.debug_validate_redirect_target("https://redirect-target.example.com/")
      true.should be_true # no exception raised
    end

    it "raises DNSError when URL is invalid" do
      cfg = Fetcher::RequestConfig.new
      mock = Fetcher::TrackingMockValidator.new
      mock.valid = false
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      expect_raises(Fetcher::DNSError) do
        client.debug_validate_redirect_target("https://bad-redirect.example.com/")
      end
    end

    it "raises DNSError when URL is not resolvable" do
      cfg = Fetcher::RequestConfig.new
      mock = Fetcher::TrackingMockValidator.new
      mock.valid = true
      mock.resolvable = false
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      expect_raises(Fetcher::DNSError) do
        client.debug_validate_redirect_target("https://unresolvable.example.com/")
      end
    end

    it "calls resolve_and_validate with the redirect URL" do
      cfg = Fetcher::RequestConfig.new
      mock = Fetcher::TrackingMockValidator.new
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      client.debug_validate_redirect_target("https://captured.example.com/path")
      mock.resolve_calls.should contain("https://captured.example.com/path")
    end
  end
end
