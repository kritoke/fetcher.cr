require "spec"
require "../src/fetcher"

# Regression guard rail for Fetcher::CrestHttpClient's public API surface.
#
# Callers across the codebase (fetcher.cr, software/*, youtube, json_feed, rss,
# reddit) depend on this surface remaining stable through the refactor
# (fetcherc-9el epic). If a method is renamed or removed, this spec will
# fail loudly so the refactorer can either update all call sites in the
# same commit or preserve the API.
#
# This is intentionally a *light* surface test. It primarily asserts
# the documented public methods exist with the documented signatures
# and are callable. A handful of methods (.with_cache, .dns_max_entries,
# the DNS shims) get a small behavior check too because pure existence
# would let a no-op rename slip through. It complements the
# behavior-driven specs in spec/crest_http_client_*_spec.cr.
describe Fetcher::CrestHttpClient do
  describe "public class API" do
    it "exposes a default constructor" do
      Fetcher::CrestHttpClient.new.should be_a(Fetcher::CrestHttpClient)
    end

    it "exposes a constructor that accepts a config and optional validator" do
      config = Fetcher::RequestConfig.new
      validator = Fetcher::URLValidator.default_service
      Fetcher::CrestHttpClient.new(config, validator).should be_a(Fetcher::CrestHttpClient)
    end

    it "exposes .build_headers(::HTTP::Headers) class method" do
      result = Fetcher::CrestHttpClient.build_headers(HTTP::Headers.new)
      result.should be_a(HTTP::Headers)
    end

    it "exposes .with_cache(::HTTP::Headers, String?, String?) class method" do
      base = HTTP::Headers.new
      result = Fetcher::CrestHttpClient.with_cache(base, "etag-value", "Wed, 21 Oct 2015 07:28:00 GMT")
      result["If-None-Match"].should eq "etag-value"
      result["If-Modified-Since"].should eq "Wed, 21 Oct 2015 07:28:00 GMT"
    end

    it "exposes .clear_rate_limiters class method" do
      Fetcher::CrestHttpClient.clear_rate_limiters.should be_nil
    end

    it "exposes .clear_dns_cache class method" do
      Fetcher::CrestHttpClient.clear_dns_cache.should be_nil
    end

    it "exposes .dns_max_entries class accessor (read + write)" do
      original = Fetcher::CrestHttpClient.dns_max_entries
      begin
        Fetcher::CrestHttpClient.dns_max_entries = 1234
        Fetcher::CrestHttpClient.dns_max_entries.should eq 1234
      ensure
        Fetcher::CrestHttpClient.dns_max_entries = original
      end
    end

    # The five shim methods below delegate to Fetcher::DnsCache. They
    # are part of the public API surface (see fetcherc-9el.1) and need
    # to be guarded here so a refactor that drops or renames them is
    # caught at review time.

    it "exposes .ensure_dns_cleanup_registered class method" do
      Fetcher::CrestHttpClient.ensure_dns_cleanup_registered.should be_nil
    end

    it "exposes .clear_expired_dns class method" do
      Fetcher::CrestHttpClient.clear_expired_dns.should be_nil
    end

    it "exposes .enforce_dns_limit class method" do
      Fetcher::CrestHttpClient.enforce_dns_limit.should be_nil
    end
  end

  describe "public instance API" do
    it "exposes #head" do
      client = Fetcher::CrestHttpClient.new
      client.responds_to?(:head).should be_true
    end

    it "exposes #get" do
      client = Fetcher::CrestHttpClient.new
      client.responds_to?(:get).should be_true
    end

    it "exposes #clear_dns_cache (instance)" do
      client = Fetcher::CrestHttpClient.new
      client.clear_dns_cache.should be_nil
    end
  end
end
