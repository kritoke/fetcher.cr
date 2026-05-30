require "crest"
require "base64"
require "json"
require "./request_config"
require "./header_builder"
require "./config"
require "./exceptions"

module Fetcher
  module RedditOAuth
    Log = ::Log.for("fetcher.reddit")

    TOKEN_ENDPOINT       = "https://www.reddit.com/api/v1/access_token"
    TOKEN_REFRESH_BUFFER = 60

    record CachedToken,
      access_token : String,
      # Absolute timestamp when the token expires
      expires_at : Time

    # Token storage keyed by client_id to support multi-tenant usage
    @@token_cache = {} of String => CachedToken
    @@mutex = Mutex.new

    def self.get_token(config : RequestConfig) : String?
      client_id = config.reddit_client_id
      client_secret = config.reddit_client_secret
      username = config.reddit_username
      password = config.reddit_password

      unless client_id && client_secret && username && password
        Log.debug { "No Reddit OAuth credentials configured, using unauthenticated requests" }
        return
      end

      @@mutex.synchronize do
        if (cached = @@token_cache[client_id]?) && !token_expired?(cached)
          remaining = (cached.expires_at - Time.utc).to_i
          Log.debug { "Using cached Reddit OAuth token for #{client_id} (expires in #{remaining}s)" }
          return cached.access_token
        end

        acquire_new_token(client_id, client_secret, username, password)
      end
    end

    def self.clear_token : Nil
      clear_token(nil)
    end

    def self.clear_token(client_id : String?) : Nil
      @@mutex.synchronize do
        if client_id
          @@token_cache.delete(client_id)
        else
          @@token_cache.clear
        end
      end
    end

    private def self.token_expired?(token : CachedToken) : Bool
      # Treat expires_at as an absolute Time; refresh if within buffer
      Time.utc > (token.expires_at - TOKEN_REFRESH_BUFFER.seconds)
    end

    private def self.truncate_body(body : String, max : Int32 = 256) : String?
      body[0, max].gsub(/\s+/, " ").strip
    rescue ex
      Log.debug { "Failed to truncate OAuth response body: #{ex.message}" }
      nil
    end

    private def self.acquire_new_token(client_id : String, client_secret : String, username : String, password : String) : String?
      basic_auth = Base64.strict_encode("#{client_id}:#{client_secret}")

      headers = HeaderBuilder.build_for_crest(::HTTP::Headers{
        "User-Agent"    => Reddit::USER_AGENT,
        "Authorization" => "Basic #{basic_auth}",
        "Content-Type"  => "application/x-www-form-urlencoded",
      })

      form = Hash(String, String){
        "grant_type" => "password",
        "username"   => username,
        "password"   => password,
      }

      response = Crest::Request.execute(
        :post,
        TOKEN_ENDPOINT,
        headers: headers,
        form: form,
        max_redirects: 0,
        handle_errors: false,
        connect_timeout: Config::DEFAULT_CONNECT_TIMEOUT,
        read_timeout: Config::DEFAULT_READ_TIMEOUT,
      )

      unless response.status_code == 200
        body_snippet = truncate_body(response.body)
        Log.error { "Reddit OAuth token request failed: status=#{response.status_code} body=#{body_snippet}" }
        raise RedditOAuthError.new("OAuth token request failed: HTTP #{response.status_code}")
      end

      parsed = JSON.parse(response.body)
      access_token = parsed["access_token"].as_s
      expires_in = parsed["expires_in"]?.try(&.as_i) || 3600

      @@token_cache[client_id] = CachedToken.new(
        access_token: access_token,
        expires_at: Time.utc + expires_in.seconds
      )

      Log.info { "Reddit OAuth token acquired for #{client_id}, expires in #{expires_in}s" }
      access_token
    rescue ex : JSON::ParseException
      Log.error { "Failed to parse Reddit OAuth response: #{ex.message}" }
      raise RedditOAuthError.new("Failed to parse OAuth token response", cause: ex)
    rescue ex : Crest::RequestFailed
      Log.error { "Reddit OAuth request failed: #{ex.message}" }
      raise RedditOAuthError.new("OAuth request failed: #{ex.message}", cause: ex)
    rescue ex : RedditOAuthError
      raise ex
    rescue ex
      Log.error { "Reddit OAuth error: #{ex.class} - #{ex.message}" }
      raise RedditOAuthError.new("OAuth error: #{ex.message}", cause: ex)
    end
  end
end
