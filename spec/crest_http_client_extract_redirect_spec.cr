require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"

# Minimal fake Crest::Response to simulate headers
module Crest
  class Response
    getter headers : Hash(String, String | Array(String))
    def initialize(headers)
      @headers = headers
      @http_client_res = nil
      @request = nil
      @status_code = 0
      @body = ""
    end
  end
end

describe Fetcher::CrestHttpClient do
  it "extracts first Location when header is an array" do
    client = Fetcher::CrestHttpClient.new
    headers = {"location" => [" https://a.example/ ", "https://b.example/"]} of String => String | Array(String)
    client.debug_extract_redirect_url(headers).should eq("https://a.example/")
  end

  it "raises when Location header missing or empty" do
    client = Fetcher::CrestHttpClient.new
    headers = {} of String => String | Array(String)
    ->{ client.debug_extract_redirect_url(headers) }.should raise_error(Fetcher::MissingLocationHeaderError)

    headers2 = {"location" => ["   "]} of String => String | Array(String)
    ->{ client.debug_extract_redirect_url(headers2) }.should raise_error(Fetcher::MissingLocationHeaderError)
  end
end
