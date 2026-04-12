require "spec"
require "../src/fetcher"

describe "Fetcher::Reddit old.reddit.com fallback" do
  describe "old_ttl_for_sort" do
    it "returns 5 minutes for new" do
      Fetcher::Reddit.old_ttl_for_sort("new").should eq(5.minutes)
    end

    it "returns 5 minutes for rising" do
      Fetcher::Reddit.old_ttl_for_sort("rising").should eq(5.minutes)
    end

    it "returns 15 minutes for hot" do
      Fetcher::Reddit.old_ttl_for_sort("hot").should eq(15.minutes)
    end

    it "returns 30 minutes for top" do
      Fetcher::Reddit.old_ttl_for_sort("top").should eq(30.minutes)
    end

    it "returns 30 minutes for controversial" do
      Fetcher::Reddit.old_ttl_for_sort("controversial").should eq(30.minutes)
    end

    it "returns 15 minutes for unknown sort" do
      Fetcher::Reddit.old_ttl_for_sort("unknown").should eq(15.minutes)
    end

    it "returns longer TTLs than standard ttl_for_sort" do
      ["new", "rising", "hot", "top", "controversial"].each do |sort|
        Fetcher::Reddit.old_ttl_for_sort(sort).should be > Fetcher::Reddit.ttl_for_sort(sort)
      end
    end
  end

  describe "constants" do
    it "defines OLD_REDDIT_API_BASE" do
      Fetcher::Reddit::OLD_REDDIT_API_BASE.should eq("https://old.reddit.com")
    end

    it "defines old Reddit cache TTL constants" do
      # Ensure mapping provides expected values
      Fetcher::Reddit.old_ttl_for_sort("new").should eq(5.minutes)
      Fetcher::Reddit.old_ttl_for_sort("rising").should eq(5.minutes)
      Fetcher::Reddit.old_ttl_for_sort("hot").should eq(15.minutes)
      Fetcher::Reddit.old_ttl_for_sort("top").should eq(30.minutes)
      Fetcher::Reddit.old_ttl_for_sort("controversial").should eq(30.minutes)
      Fetcher::Reddit.old_ttl_for_sort("unknown").should eq(15.minutes)
    end
  end

  describe "parse_reddit_response with old.reddit.com data" do
    it "parses Reddit JSON from old.reddit.com and uses www.reddit.com for discussion URLs" do
      reddit_json = <<-JSON
        [
          {
            "kind": "Listing",
            "data": {
              "children": [
                {
                  "kind": "t3",
                  "data": {
                    "title": "Crystal 1.0 Released",
                    "url": "https://crystal-lang.org",
                    "permalink": "/r/crystal/comments/abc123/crystal_10_released/",
                    "created_utc": 1705315800.0,
                    "is_self": false
                  }
                }
              ]
            }
          }
        ]
        JSON

      entries = Fetcher::Reddit.parse_reddit_response(reddit_json, 10)
      entries.size.should eq(1)

      entry = entries.first
      entry.title.should eq("Crystal 1.0 Released")
      entry.url.should eq("https://crystal-lang.org")
      entry.comment_url.should eq("https://www.reddit.com/r/crystal/comments/abc123/crystal_10_released/")
      entry.source_type.should eq(Fetcher::SourceType::Reddit)
    end

    it "uses www.reddit.com for self posts too" do
      reddit_json = <<-JSON
        [
          {
            "kind": "Listing",
            "data": {
              "children": [
                {
                  "kind": "t3",
                  "data": {
                    "title": "Self Post",
                    "url": "https://www.reddit.com/r/crystal/comments/self123/",
                    "permalink": "/r/crystal/comments/self123/self_post/",
                    "created_utc": 1705315800.0,
                    "is_self": true
                  }
                }
              ]
            }
          }
        ]
        JSON

      entries = Fetcher::Reddit.parse_reddit_response(reddit_json, 10)
      entry = entries.first
      entry.url.should eq("https://www.reddit.com/r/crystal/comments/self123/self_post/")
      entry.comment_url.should eq("https://www.reddit.com/r/crystal/comments/self123/self_post/")
    end
  end
end
