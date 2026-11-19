require "spec"
require "../src/fetcher"

private def ok_result : Fetcher::Result
  Fetcher::Result.success([] of Fetcher::Entry)
end

private def err_result(status : Int32, message : String = "HTTP #{status}") : Fetcher::Result
  Fetcher::Result.error(Fetcher::Error.http(status, message, "https://www.reddit.com/r/sysadmin/hot.json"))
end

describe "Fetcher::Reddit.run_strategies" do
  it "returns the API result without trying fallbacks on success" do
    calls = [] of Symbol
    outcome = Fetcher::Reddit.run_strategies("sysadmin",
      api: -> { calls << :api; ok_result },
      rss: -> { calls << :rss; ok_result },
      old_reddit: -> { calls << :old; ok_result })

    outcome[:source].should eq(:api)
    calls.should eq([:api])
  end

  it "tries RSS when the API returns 403" do
    calls = [] of Symbol
    outcome = Fetcher::Reddit.run_strategies("sysadmin",
      api: -> { calls << :api; err_result(403) },
      rss: -> { calls << :rss; ok_result },
      old_reddit: -> { calls << :old; ok_result })

    outcome[:source].should eq(:rss)
    calls.should eq([:api, :rss])
  end

  it "reports the API 403, not old.reddit's 404, when every strategy fails" do
    outcome = Fetcher::Reddit.run_strategies("sysadmin",
      api: -> { err_result(403, "HTTP error 403: <huge html body>") },
      rss: -> { err_result(403) },
      old_reddit: -> { err_result(404, "Subreddit 'sysadmin' not found") })

    outcome[:source].should eq(:failed)
    error = outcome[:result].error.should_not be_nil
    error.status_code.should eq(403)
    error.message.should contain("blocked request (HTTP 403)")
    error.message.should contain("RSS fallback")
    error.message.should_not contain("not found")
    error.message.should_not contain("huge html body")
  end

  it "reports not found only when the primary API returned 404" do
    outcome = Fetcher::Reddit.run_strategies("nosuchsub",
      api: -> { err_result(404) },
      rss: -> { ok_result },
      old_reddit: -> { err_result(404) })

    outcome[:source].should eq(:failed)
    error = outcome[:result].error.should_not be_nil
    error.message.should eq("Subreddit 'nosuchsub' not found")
  end

  it "skips RSS for non-403 client errors" do
    calls = [] of Symbol
    Fetcher::Reddit.run_strategies("sysadmin",
      api: -> { calls << :api; err_result(401) },
      rss: -> { calls << :rss; ok_result },
      old_reddit: -> { calls << :old; err_result(401) })

    calls.should eq([:api, :old])
  end
end

describe "Fetcher::Reddit.attempt_with_retry" do
  it "preserves the HTTP status that with_retry would otherwise drop" do
    config = Fetcher::RequestConfig.new.with_retry_max_retries(0)
    result = Fetcher::Reddit.attempt_with_retry(config) do
      inner = Fetcher::Error.http(403, "HTTP error 403", "https://www.reddit.com/r/x/hot.json")
      raise Fetcher::Reddit::RedditFetchError.new(inner.message, Fetcher::HTTPError.new(inner.message, 403, inner))
    end

    error = result.error.should_not be_nil
    error.status_code.should eq(403)
    error.kind.should eq(Fetcher::ErrorKind::HTTPError)
  end
end
