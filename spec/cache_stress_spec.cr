require "spec"
require "../src/fetcher"

describe "CacheStore stress" do
  it "survives concurrent access without errors" do
    cache = Fetcher::Cache.new(max_size: 100, enabled: true)

    completions = [] of Channel(Nil)
    50.times do |i|
      ch = Channel(Nil).new
      completions << ch
      spawn do
        200.times do |j|
          key = "key_#{j % 50}"
          res = Fetcher::Result.success(entries: [] of Fetcher::Entry, site_link: "https://#{i}-#{j}.example")
          cache.set(key, res, 5.minutes)
          cached = cache.get(key)
          # occasionally check stats
          if j % 20 == 0
            s = cache.stats
            s.hits.should be_a(UInt64)
            s.misses.should be_a(UInt64)
          end
        end
        ch.send(nil)
      end
    end

    # wait for completions
    completions.each { |c| c.receive }
  end
end
