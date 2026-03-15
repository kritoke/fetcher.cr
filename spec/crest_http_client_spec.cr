require "spec"
require "../src/fetcher/crest_http_client"

describe Fetcher::CrestHttpClient do
  it "should initialize with default config" do
    client = Fetcher::CrestHttpClient.new
    client.should_not be_nil
  end

  it "should handle DNSError" do
    client = Fetcher::CrestHttpClient.new
    expect_raises(Fetcher::CrestHttpClient::DNSError) do
      # This should raise a DNSError for invalid URL
      client.get("http://invalid-url-that-does-not-exist-12345.com")
    end
  end

  it "should build headers correctly" do
    custom_headers = HTTP::Headers{"X-Custom" => "test"}
    headers = Fetcher::CrestHttpClient.build_headers(custom_headers)

    headers["User-Agent"].should_not be_nil
    headers["Accept"].should_not be_nil
    headers["X-Custom"].should eq "test"
  end

  it "should add cache headers correctly" do
    base_headers = HTTP::Headers{"User-Agent" => "test"}
    etag = "abc123"
    last_modified = "Wed, 21 Oct 2015 07:28:00 GMT"

    cached_headers = Fetcher::CrestHttpClient.with_cache(base_headers, etag, last_modified)

    cached_headers["If-None-Match"].should eq etag
    cached_headers["If-Modified-Since"].should eq last_modified
  end
end
