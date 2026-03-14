require "spec"
require "../src/fetcher/domain_batch_processor"

describe Fetcher::DomainBatchProcessor do
  it "should group URLs by domain" do
    urls = [
      "https://example.com/feed1",
      "https://example.com/feed2",
      "https://test.com/feed1",
      "https://example.com/feed3",
    ]

    groups = Fetcher::DomainBatchProcessor.group_by_domain(urls)

    groups.size.should eq 2
    groups["example.com"].size.should eq 3
    groups["test.com"].size.should eq 1
  end

  it "should handle invalid URLs" do
    urls = [
      "https://example.com/feed1",
      "invalid-url",
      "https://test.com/feed1",
    ]

    groups = Fetcher::DomainBatchProcessor.group_by_domain(urls)

    # "invalid-url" parses successfully but has no host, so it goes to "default"
    groups["default"].size.should eq 1
    groups["example.com"].size.should eq 1
    groups["test.com"].size.should eq 1
  end

  it "should handle URLs without host" do
    urls = [
      "/local/feed",
      "https://example.com/feed",
    ]

    groups = Fetcher::DomainBatchProcessor.group_by_domain(urls)

    groups["default"].size.should eq 1
    groups["example.com"].size.should eq 1
  end
end
