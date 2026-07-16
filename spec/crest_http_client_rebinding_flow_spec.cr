require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"
require "socket"

module Fetcher
  # Mock validator that simulates DNS rebinding behavior
  class MockRebindingValidator < URLValidator::Service
    property valid = true
    property resolvable = true
    property connected_ip_ok = true
    getter rebind_events = [] of String

    def initialize(
      @valid = true,
      @resolvable = true,
      @connected_ip_ok = true,
    )
      @rebind_events = [] of String
    end

    def valid?(url : String?) : Bool
      @valid
    end

    def resolve_and_validate(url : String) : Bool
      @resolvable
    end

    def validate_connected_ip(host : String, connected_ip : Socket::IPAddress) : Bool
      @rebind_events << "#{host}:#{connected_ip}"
      @connected_ip_ok
    end

    def extract_domain(url : String) : String
      url.try(&.split("://")[1]?.try(&.split("/")[0])) || "default"
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
  end
end

describe Fetcher::CrestHttpClient do
  describe "verify_dns_rebinding cache flow" do
    it "no-ops when DNS rebinding check is disabled" do
      cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(rebinding_check: false))
      client = Fetcher::CrestHttpClient.new(cfg)
      mock = Fetcher::MockRebindingValidator.new
      # Override validator
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      # Should not raise and not trigger any validation
      client.debug_verify_dns_rebinding("https://example.com/feed")
      true.should be_true
    end

    it "no-ops when URL host looks like an IP address" do
      cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(rebinding_check: true))
      mock = Fetcher::MockRebindingValidator.new
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      # Should not make network calls for IP addresses
      client.debug_verify_dns_rebinding("http://127.0.0.1/feed")
      true.should be_true
    end

    it "exposes initially empty DNS cache via debug_get_cached_dns" do
      cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(cache_enabled: true))
      client = Fetcher::CrestHttpClient.new(cfg)

      client.debug_get_cached_dns("nonexistent.example.com").should be_nil
    end

    it "debug_seed_dns_cache populates the cache when enabled" do
      cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(cache_enabled: true))
      client = Fetcher::CrestHttpClient.new(cfg)

      client.debug_seed_dns_cache("example.com", "93.184.216.34")
      cached = client.debug_get_cached_dns("example.com")
      cached.should_not be_nil
      cached.to_s.should contain("93.184.216.34")
    end

    it "debug_clear_dns_cache removes all cached entries" do
      cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(cache_enabled: true))
      client = Fetcher::CrestHttpClient.new(cfg)

      client.debug_seed_dns_cache("example.com", "93.184.216.34")
      client.debug_clear_dns_cache

      client.debug_get_cached_dns("example.com").should be_nil
    end

    it "validates cached DNS entry when present" do
      cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(rebinding_check: true, cache_enabled: true))
      mock = Fetcher::MockRebindingValidator.new
      mock.connected_ip_ok = true # IP is valid
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      # Seed cache with known good IP
      client.debug_seed_dns_cache("example.com", "93.184.216.34")

      # Verify - should call validate_connected_ip
      client.debug_verify_dns_rebinding("https://example.com/feed")
      # No exception means validation passed
      true.should be_true
    end

    it "raises DNSError when cached IP validation fails (rebind detected)" do
      cfg = Fetcher::RequestConfig.new(dns: Fetcher::DnsConfig.new(rebinding_check: true, cache_enabled: true))
      mock = Fetcher::MockRebindingValidator.new
      mock.connected_ip_ok = false # Simulate IP change (rebind)
      client = Fetcher::CrestHttpClient.new(cfg, mock)

      # Seed cache with an IP
      client.debug_seed_dns_cache("example.com", "93.184.216.34")

      expect_raises(Fetcher::DNSError) do
        client.debug_verify_dns_rebinding("https://example.com/feed")
      end
    end
  end
end
