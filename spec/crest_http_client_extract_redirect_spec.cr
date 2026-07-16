require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"

describe Fetcher::CrestHttpClient do
  it "extracts first Location when header is an array" do
    client = Fetcher::CrestHttpClient.new
    headers = {"location" => [" https://a.example/ ", "https://b.example/"]} of String => String | Array(String)
    client.debug_extract_redirect_url(headers).should eq("https://a.example/")
  end

  it "raises when Location header missing or empty" do
    client = Fetcher::CrestHttpClient.new
    headers = {} of String => String | Array(String)
    expect_raises(Fetcher::MissingLocationHeaderError) do
      client.debug_extract_redirect_url(headers)
    end

    headers2 = {"location" => ["   "]} of String => String | Array(String)
    expect_raises(Fetcher::MissingLocationHeaderError) do
      client.debug_extract_redirect_url(headers2)
    end
  end
end
