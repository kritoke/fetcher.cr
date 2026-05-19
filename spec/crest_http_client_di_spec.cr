require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"
require "uri"

module Fetcher
  class MockValidator < URLValidator::Service
    def initialize(@valid = true, @resolvable = true, @connected_ip_ok = true)
    end

    def valid?(url : String?) : Bool
      @valid
    end

    def resolve_and_validate(url : String) : Bool
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
      # Simple heuristic for tests: numeric hosts look like IPs
      host.size > 0 && host[0].ascii_number?
    end

    def validate_ip(host : String) : Bool
      !host.starts_with?("10.")
    end

    def register_ip(host : String, ip : Socket::IPAddress) : Nil
      # no-op for tests
    end
  end
end

describe Fetcher::CrestHttpClient do
  it "uses injected validator for validate_redirect_target (allowed)" do
    cfg = Fetcher::RequestConfig.new
    mock = Fetcher::MockValidator.new(true, true)
    client = Fetcher::CrestHttpClient.new(cfg, mock)

    # Should not raise when validator reports target is valid and resolvable
    client.debug_validate_redirect_target("https://example.com/feed")
    true.should be_true
  end

  it "uses injected validator for validate_redirect_target (blocked)" do
    cfg = Fetcher::RequestConfig.new
    mock = Fetcher::MockValidator.new(false, false)
    client = Fetcher::CrestHttpClient.new(cfg, mock)

    begin
      client.debug_validate_redirect_target("https://bad.example.com/feed")
      raise "expected DNSError"
    rescue Fetcher::DNSError
      # expected
    end
  end

  it "uses injected validator for check_ssrf (allowed)" do
    cfg = Fetcher::RequestConfig.new
    mock = Fetcher::MockValidator.new(true, true)
    client = Fetcher::CrestHttpClient.new(cfg, mock)

    client.debug_check_ssrf("https://safe.example.com/feed")
    true.should be_true
  end

  it "uses injected validator for check_ssrf (blocked)" do
    cfg = Fetcher::RequestConfig.new
    mock = Fetcher::MockValidator.new(true, false)
    client = Fetcher::CrestHttpClient.new(cfg, mock)

    begin
      client.debug_check_ssrf("https://unsafe.example.com/feed")
      raise "expected DNSError"
    rescue Fetcher::DNSError
      # expected
    end
  end
end
