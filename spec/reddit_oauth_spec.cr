require "spec"
require "../src/fetcher"

describe Fetcher::RedditOAuth do
  describe "get_token" do
    it "returns nil when no credentials are configured" do
      config = Fetcher::RequestConfig.new
      Fetcher::RedditOAuth.get_token(config).should be_nil
    end

    it "returns nil when only some credentials are configured" do
      config = Fetcher::RequestConfig.new(
        reddit_client_id: "id",
        reddit_client_secret: "secret"
      )
      Fetcher::RedditOAuth.get_token(config).should be_nil
    end

    it "returns nil when username/password are missing" do
      config = Fetcher::RequestConfig.new(
        reddit_client_id: "id",
        reddit_client_secret: "secret",
        reddit_username: "user"
      )
      Fetcher::RedditOAuth.get_token(config).should be_nil
    end

    it "returns nil when password is missing" do
      config = Fetcher::RequestConfig.new(
        reddit_client_id: "id",
        reddit_client_secret: "secret",
        reddit_password: "pass"
      )
      Fetcher::RedditOAuth.get_token(config).should be_nil
    end

    it "raises RedditOAuthError on invalid credentials (non-200 response)" do
      config = Fetcher::RequestConfig.new(
        reddit_client_id: "invalid_client_id_that_will_fail",
        reddit_client_secret: "invalid_secret",
        reddit_username: "invalid_user",
        reddit_password: "invalid_pass"
      )
      Fetcher::RedditOAuth.clear_token
      expect_raises(Fetcher::RedditOAuthError) do
        Fetcher::RedditOAuth.get_token(config)
      end
    end
  end

  describe "CachedToken" do
    it "stores access_token and expires_at (absolute Time)" do
      now = Time.utc
      token = Fetcher::RedditOAuth::CachedToken.new(
        access_token: "test_token",
        expires_at: now + 3600.seconds
      )
      token.access_token.should eq("test_token")
      token.expires_at.should eq(now + 3600.seconds)
    end
  end

  describe "clear_token" do
    it "clears cached token without error" do
      Fetcher::RedditOAuth.clear_token
    end
  end

  describe "RequestConfig forwarding" do
    it "preserves reddit credentials through with_retry_max_retries" do
      config = Fetcher::RequestConfig.new(
        reddit_client_id: "test_id",
        reddit_client_secret: "test_secret",
        reddit_username: "test_user",
        reddit_password: "test_pass"
      )
      new_config = config.with_retry_max_retries(5)
      new_config.reddit_client_id.should eq("test_id")
      new_config.reddit_client_secret.should eq("test_secret")
      new_config.reddit_username.should eq("test_user")
      new_config.reddit_password.should eq("test_pass")
    end
  end
end
