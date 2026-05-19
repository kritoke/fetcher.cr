require "spec"
require "./support/crest_http_client_test_helpers"
require "../src/fetcher"

describe "Registrable-domain aware redirects" do
  it "allows redirects between different subdomains of same registrable domain" do
    client = Fetcher::CrestHttpClient.new
    # blog.malwarebytes.com -> www.malwarebytes.com should be allowed
    client.debug_allow_redirect?("blog.malwarebytes.com", "www.malwarebytes.com").should be_true
  end

  it "blocks redirects between different registrable domains" do
    client = Fetcher::CrestHttpClient.new
    # www.theregister.co.uk -> www.theregister.com should be treated as external
    client.debug_allow_redirect?("www.theregister.co.uk", "www.theregister.com").should be_false
  end
end
