require "spec"
require "../src/fetcher"

describe Fetcher::PublicSuffix do
  describe "load_rules" do
    it "loads rules only once (idempotent)" do
      # Call twice - should not reload
      Fetcher::PublicSuffix.load_rules
      first_load = Fetcher::PublicSuffix.get_public_suffix("example.com")

      Fetcher::PublicSuffix.load_rules
      second_load = Fetcher::PublicSuffix.get_public_suffix("example.com")

      first_load.should eq(second_load)
    end

    it "loads rules from file or fallback" do
      # Should not raise regardless of file existence
      Fetcher::PublicSuffix.load_rules
      true.should be_true
    end
  end

  describe "get_public_suffix" do
    it "returns correct suffix for .com domains" do
      Fetcher::PublicSuffix.get_public_suffix("example.com").should eq("com")
      Fetcher::PublicSuffix.get_public_suffix("www.example.com").should eq("com")
      Fetcher::PublicSuffix.get_public_suffix("sub.www.example.com").should eq("com")
    end

    it "returns correct suffix for .org domains" do
      Fetcher::PublicSuffix.get_public_suffix("example.org").should eq("org")
    end

    it "returns correct suffix for .co.uk multi-part TLD" do
      result = Fetcher::PublicSuffix.get_public_suffix("example.co.uk")
      result.should eq("co.uk")
    end

    it "handles case insensitivity" do
      Fetcher::PublicSuffix.get_public_suffix("EXAMPLE.COM").should eq("com")
      Fetcher::PublicSuffix.get_public_suffix("Example.Co.UK").should eq("co.uk")
    end

    it "returns last label for unknown TLD" do
      result = Fetcher::PublicSuffix.get_public_suffix("example.unknown")
      result.should eq("unknown")
    end

    it "handles single label domain" do
      result = Fetcher::PublicSuffix.get_public_suffix("localhost")
      result.should eq("localhost")
    end
  end

  describe "registrable_domain" do
    it "returns domain itself for single label" do
      result = Fetcher::PublicSuffix.registrable_domain("localhost")
      result.should eq("localhost")
    end

    it "returns domain itself for simple TLD" do
      result = Fetcher::PublicSuffix.registrable_domain("example.com")
      result.should eq("example.com")
    end

    it "returns domain itself for www" do
      result = Fetcher::PublicSuffix.registrable_domain("www.example.com")
      result.should eq("example.com")
    end

    it "returns domain itself for subdomains" do
      result = Fetcher::PublicSuffix.registrable_domain("blog.example.com")
      result.should eq("example.com")
      result = Fetcher::PublicSuffix.registrable_domain("api.blog.example.com")
      result.should eq("example.com")
    end

    it "handles multi-part TLD like .co.uk" do
      result = Fetcher::PublicSuffix.registrable_domain("example.co.uk")
      result.should eq("example.co.uk")
      result = Fetcher::PublicSuffix.registrable_domain("www.example.co.uk")
      result.should eq("example.co.uk")
    end

    it "returns IP addresses as-is" do
      result = Fetcher::PublicSuffix.registrable_domain("192.168.1.1")
      result.should eq("192.168.1.1")
    end

    it "rejects malformed IP addresses (out-of-range octets)" do
      # The previous regex %r{^\d+\.\d+\.\d+\.\d+$} accepted any four
      # numeric groups, including 999.999.999.999. After switching to
      # Socket::IPAddress validation, these should be treated as hostnames,
      # not returned verbatim as if they were valid IPs.
      Fetcher::PublicSuffix.registrable_domain("999.999.999.999").should_not eq("999.999.999.999")
      Fetcher::PublicSuffix.registrable_domain("256.0.0.1").should_not eq("256.0.0.1")
    end

    it "handles case insensitivity" do
      result = Fetcher::PublicSuffix.registrable_domain("WWW.EXAMPLE.COM")
      result.should eq("example.com")
    end

    it "returns nil for empty string" do
      result = Fetcher::PublicSuffix.registrable_domain("")
      result.should be_nil
    end

    it "handles unknown TLD gracefully" do
      result = Fetcher::PublicSuffix.registrable_domain("example.xyz")
      result.should eq("example.xyz")
    end
  end
end
