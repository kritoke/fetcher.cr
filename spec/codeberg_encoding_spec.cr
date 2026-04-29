require "spec"
require "../src/fetcher"

describe "Codeberg provider URL encoding" do
  it "encodes repo path segments for API URLs" do
    repo = "supercell/luce:cb"
    provider = Fetcher::Software.debug_build_codeberg_provider(repo)

    # Ensure ':' is percent-encoded in the API URL path
    provider.api_url.includes?("supercell/luce%3Acb").should be_true
    provider.atom_url.includes?("supercell/luce%3Acb").should be_true
  end
end
