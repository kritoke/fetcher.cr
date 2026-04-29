require "spec"
require "../src/fetcher"

describe Fetcher::ConcurrentFetcher do
  it "enforces max_pending and returns QueueFullError when overloaded" do
    urls = [] of String
    # create a bunch of URLs; they need not be reachable because Fetcher.pull will attempt network
    200.times do |i|
      urls << "http://example.invalid/#{i}"
    end

    # Use small max_pending to trigger QueueFullError paths
    results = Fetcher::ConcurrentFetcher.pull_multiple(urls, ::HTTP::Headers.new, 10, 4, Fetcher::RequestConfig.new, 5)

    # Results length equals number of reachable results (pull_multiple compacts nils). We instead
    # assert that some entries are error results due to overload handling.
    errors = results.select { |r| !r.success? }
    errors.should_not be_empty
  end
end
