require "spec"
require "../../src/fetcher"

describe "Integration Tests - Reddit" do
  describe "Reddit JSON parsing" do
    it "parses valid Reddit JSON structure" do
      reddit_json = <<-JSON
        [
          {
            "kind": "Listing",
            "data": {
              "children": [
                {
                  "kind": "t3",
                  "data": {
                    "title": "Test Post",
                    "url": "https://example.com",
                    "permalink": "/r/crystal/comments/test/",
                    "created_utc": 1705315800.0,
                    "is_self": false
                  }
                }
              ]
            }
          }
        ]
        JSON

      parsed = JSON.parse(reddit_json)
      children = parsed[0]["data"]["children"]
      children.should_not be_nil
      children.as_a.size.should eq(1)

      post = children[0]["data"]
      post["title"].as_s.should eq("Test Post")
      post["created_utc"].as_f.should eq(1705315800.0)
    end
  end
end
