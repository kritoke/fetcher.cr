require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"

describe Fetcher::CrestHttpClient do
  it "allows redirects from www -> apex domain" do
    client = Fetcher::CrestHttpClient.new
    client.debug_allow_redirect?("www.kffhealthnews.org", "kffhealthnews.org").should be_true
  end

  it "allows redirects from apex -> www domain" do
    client = Fetcher::CrestHttpClient.new
    client.debug_allow_redirect?("kffhealthnews.org", "www.kffhealthnews.org").should be_true
  end
end
