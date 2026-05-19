require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"

describe Fetcher::CrestHttpClient do
  it "no-ops when DNS rebinding check is disabled (network-free)" do
    cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(rebinding_check: false))
    client = Fetcher::CrestHttpClient.new(cfg)
    # Should not raise and simply return
    client.debug_verify_dns_rebinding("https://example.com/feed")
    true.should be_true
  end

  it "no-ops when URL host is an IP address (network-free)" do
    cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(rebinding_check: true))
    client = Fetcher::CrestHttpClient.new(cfg)
    # Using an IP host causes valid_host? to return false and avoid network resolution
    client.debug_verify_dns_rebinding("http://127.0.0.1/feed")
    true.should be_true
  end

  it "exposes an initially empty DNS cache via debug_get_cached_dns" do
    client = Fetcher::CrestHttpClient.new
    client.debug_get_cached_dns("example.com").should be_nil
    client.debug_clear_dns_cache
    client.debug_get_cached_dns("example.com").should be_nil
  end
end
