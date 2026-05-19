require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"

module Fetcher
  class MockValidator2 < URLValidator::Service
    def initialize(connected_ip_ok = true)
      @connected_ip_ok = connected_ip_ok
    end

    def valid?(url : String?) : Bool
      true
    end

    def resolve_and_validate(url : String) : Bool
      true
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
      false
    end

    def validate_ip(host : String) : Bool
      true
    end

    def register_ip(host : String, ip : Socket::IPAddress) : Nil
      # no-op
    end
  end
end

describe Fetcher::CrestHttpClient do
  it "validate_cached_dns succeeds when validator approves cached IP" do
    cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(cache_enabled: true))
    mock = Fetcher::MockValidator2.new(true)
    client = Fetcher::CrestHttpClient.new(cfg, mock)

    client.debug_seed_dns_cache("example.com", "192.0.2.1")

    # Should not raise
    client.debug_verify_dns_rebinding("https://example.com/feed")
    true.should be_true
  end

  it "validate_cached_dns raises DNSError when validator rejects cached IP" do
    cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(cache_enabled: true))
    mock = Fetcher::MockValidator2.new(false)
    client = Fetcher::CrestHttpClient.new(cfg, mock)

    client.debug_seed_dns_cache("example.com", "192.0.2.1")

    begin
      client.debug_verify_dns_rebinding("https://example.com/feed")
      raise "expected DNSError"
    rescue Fetcher::DNSError
      # expected
    end
  end
end
