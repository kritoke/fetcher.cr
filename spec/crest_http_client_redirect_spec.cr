require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"

describe Fetcher::CrestHttpClient do
  describe "allow_redirect?" do
    # Same domain
    it "allows redirect to same domain" do
      client = Fetcher::CrestHttpClient.new
      client.debug_allow_redirect?("example.com", "example.com").should be_true
    end

    # Subdomain ↔ apex
    it "allows redirect from www to apex domain" do
      client = Fetcher::CrestHttpClient.new
      client.debug_allow_redirect?("www.example.com", "example.com").should be_true
    end

    it "allows redirect from apex to www domain" do
      client = Fetcher::CrestHttpClient.new
      client.debug_allow_redirect?("example.com", "www.example.com").should be_true
    end

    # Registrable-domain equality
    it "allows redirect between different subdomains of same registrable domain" do
      client = Fetcher::CrestHttpClient.new
      client.debug_allow_redirect?("blog.example.com", "www.example.com").should be_true
    end

    it "blocks redirect between different registrable domains" do
      client = Fetcher::CrestHttpClient.new
      client.debug_allow_redirect?("www.example.com", "www.other.com").should be_false
    end

    # allowed_domains list
    it "allows redirect when target is in allowed_domains list (exact match)" do
      cfg = Fetcher::RequestConfig.new
      cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allowed_domains: ["trusted.example.com", "partner.org"]))
      client = Fetcher::CrestHttpClient.new(cfg)
      client.debug_allow_redirect?("example.com", "trusted.example.com").should be_true
    end

    it "allows redirect when target is subdomain of allowed_domains entry" do
      cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allowed_domains: ["example.com"]))
      client = Fetcher::CrestHttpClient.new(cfg)
      client.debug_allow_redirect?("example.com", "api.example.com").should be_true
    end

    it "allows redirect to subdomains (apex -> subdomain)" do
      # The implementation allows example.com -> blog.example.com via the subdomain check
      cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allowed_domains: ["trusted.example.com"]))
      client = Fetcher::CrestHttpClient.new(cfg)
      # source_domain.ends_with?(".#{target_domain}") means "example.com".ends_with?(".untrusted.example.com") → false
      # But target_domain.ends_with?(".#{source_domain}") means "untrusted.example.com".ends_with?(".example.com") → true
      # So this redirect is allowed due to the subdomain rule, not allowed_domains
      client.debug_allow_redirect?("example.com", "untrusted.example.com").should be_true
    end

    it "blocks redirect to domain not in allowed_domains list or registrable domain" do
      cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allowed_domains: ["trusted.example.com"]))
      client = Fetcher::CrestHttpClient.new(cfg)
      # Not in allowed list and not same registrable domain
      client.debug_allow_redirect?("example.com", "completely.other.com").should be_false
    end

    # allow_external flag
    it "allows redirect when allow_external is true" do
      cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allow_external: true))
      client = Fetcher::CrestHttpClient.new(cfg)
      client.debug_allow_redirect?("example.com", "external.com").should be_true
    end

    it "blocks redirect when allow_external is false (default)" do
      cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allow_external: false))
      client = Fetcher::CrestHttpClient.new(cfg)
      client.debug_allow_redirect?("example.com", "external.com").should be_false
    end

    # Edge cases
    it "blocks redirect when allowed_domains is empty" do
      cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allowed_domains: [] of String))
      client = Fetcher::CrestHttpClient.new(cfg)
      client.debug_allow_redirect?("example.com", "other.com").should be_false
    end

    it "prefers allow_external over allowed_domains when allow_external is true" do
      cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allow_external: true, allowed_domains: ["example.com"]))
      client = Fetcher::CrestHttpClient.new(cfg)
      # Even external domain should be allowed since allow_external is true
      client.debug_allow_redirect?("example.com", "completely.external.com").should be_true
    end

    it "uses allowed_domains when allow_external is false" do
      cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allow_external: false, allowed_domains: ["trusted.com"]))
      client = Fetcher::CrestHttpClient.new(cfg)
      client.debug_allow_redirect?("example.com", "trusted.com").should be_true
      client.debug_allow_redirect?("example.com", "untrusted.com").should be_false
    end

    # Permanent external redirects (301/308)
    describe "allow_permanent_external" do
      it "allows 301 permanent redirect to external domain by default" do
        cfg = Fetcher::RequestConfig.new
        client = Fetcher::CrestHttpClient.new(cfg)
        # blogspot -> custom domain is a 301
        client.debug_allow_redirect?("googleaiblog.blogspot.com", "blog.research.google", status_code: 301).should be_true
      end

      it "allows 308 permanent redirect to external domain by default" do
        cfg = Fetcher::RequestConfig.new
        client = Fetcher::CrestHttpClient.new(cfg)
        client.debug_allow_redirect?("example.com", "other.com", status_code: 308).should be_true
      end

      it "blocks 302 temporary redirect to external domain by default" do
        cfg = Fetcher::RequestConfig.new
        client = Fetcher::CrestHttpClient.new(cfg)
        client.debug_allow_redirect?("example.com", "external.com", status_code: 302).should be_false
      end

      it "blocks 307 temporary redirect to external domain by default" do
        cfg = Fetcher::RequestConfig.new
        client = Fetcher::CrestHttpClient.new(cfg)
        client.debug_allow_redirect?("example.com", "external.com", status_code: 307).should be_false
      end

      it "blocks 303 see-other redirect to external domain by default" do
        cfg = Fetcher::RequestConfig.new
        client = Fetcher::CrestHttpClient.new(cfg)
        client.debug_allow_redirect?("example.com", "external.com", status_code: 303).should be_false
      end

      it "blocks permanent external redirect when allow_permanent_external is false" do
        cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allow_permanent_external: false))
        client = Fetcher::CrestHttpClient.new(cfg)
        client.debug_allow_redirect?("example.com", "external.com", status_code: 301).should be_false
      end

      it "same-domain redirect still works regardless of status code" do
        cfg = Fetcher::RequestConfig.new(redirect: Fetcher::RedirectConfig.new(allow_permanent_external: false))
        client = Fetcher::CrestHttpClient.new(cfg)
        client.debug_allow_redirect?("example.com", "example.com", status_code: 302).should be_true
      end

      it "blogspot to custom domain via 301 works by default" do
        cfg = Fetcher::RequestConfig.new
        client = Fetcher::CrestHttpClient.new(cfg)
        # Real-world case: googleaiblog.blogspot.com -> blog.research.google
        client.debug_allow_redirect?("googleaiblog.blogspot.com", "blog.research.google", status_code: 301).should be_true
      end
    end
  end
end