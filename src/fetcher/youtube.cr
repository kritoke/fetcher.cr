require "log"
require "./entry"
require "./result"
require "./retry"
require "./crest_http_client"
require "./rss"
require "./exceptions"
require "./error_handler"
require "./link_resolver"
require "./html_utils"

module Fetcher
  module YouTube
    YOUTUBE_RSS_BASE = "https://www.youtube.com/feeds/videos.xml?"

    YOUTUBE_CACHE_TTL         = 5.minutes
    YOUTUBE_RESOLVE_CACHE_TTL = 1.hour

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      channel_id = extract_channel(url)

      unless channel_id
        channel_id = resolve_channel_id(url, config)
        return Fetcher.error_result(ErrorKind::InvalidURL, "Not a valid YouTube channel URL. Could not resolve channel ID for #{url}") unless channel_id
      end

      cache_key = "youtube:#{channel_id}:#{limit}"

      if config.cache_config.enabled
        if cached = config.cache.get(cache_key)
          return cached
        end
      end

      rss_url = "#{YOUTUBE_RSS_BASE}channel_id=#{channel_id}"

      result = Fetcher.with_retry(config) do
        fetch_youtube(rss_url, channel_id, headers, limit, config)
      end

      if config.cache_config.enabled && result.success?
        config.cache.set(cache_key, result, YOUTUBE_CACHE_TTL)
      end

      result
    end

    def self.parse_youtube_feed(body : String, channel_id : String, limit : Int32 = 100) : Result
      parser = RSSParser.new
      entries = parser.parse_entries(body, limit)
      metadata = parser.parse_feed_metadata(body)

      youtube_entries = entries.map do |entry|
        link_data = LinkResolver.resolve_from_url(entry.url)
        Entry.create(
          title: entry.title,
          url: entry.url,
          source_type: SourceType::YouTube,
          content: entry.content,
          content_html: entry.content_html,
          author: entry.author,
          author_url: entry.author_url,
          published_at: entry.published_at,
          categories: entry.categories,
          attachments: entry.attachments,
          comment_url: link_data.comment_url,
          commentary_url: link_data.commentary_url,
          is_discussion_url: link_data.is_discussion_url
        )
      end

      Result.builder
        .entries(youtube_entries)
        .site_link("https://www.youtube.com/channel/#{channel_id}")
        .favicon("https://www.youtube.com/favicon.ico")
        .feed_title(metadata.feed_title)
        .feed_description(metadata.feed_description)
        .build
    rescue ex : InvalidFormatError
      Fetcher.error_result(ErrorKind::InvalidFormat, ex.message || "Invalid format error")
    rescue ex
      Fetcher.error_result(ErrorKind::Unknown, "Error: #{ex.class} - #{ex.message}")
    end

    private def self.fetch_youtube(rss_url : String, channel_id : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      http_client = Fetcher::CrestHttpClient.new(config)
      response = http_client.get(rss_url, headers)

      ErrorHandler.handle_response(response, rss_url) do
        parse_youtube_feed(response.body, channel_id, limit)
      end
    rescue ex : DNSError | TimeoutError | IO::TimeoutError | Socket::Error
      ErrorHandler.handle_network_error(ex, rss_url)
    rescue ex
      Log.warn { "YouTube fetch unexpected error: #{ex.class} - #{ex.message}" }
      ErrorHandler.handle_network_error(ex, rss_url)
    end

    private def self.extract_channel(url : String) : String?
      return extract_channel_id(url) if url.includes?("/channel/")
      return extract_handle_channel(url) if url.includes?("/@")
      return extract_custom_channel(url) if url.includes?("/c/")
      return extract_user_channel(url) if url.includes?("/user/")
      nil
    end

    private def self.extract_channel_id(url : String) : String?
      match = url.match(%r{youtube\.com/channel/([^/?]+)}i)
      return unless match
      id = match[1]
      id.starts_with?("UC") && id.matches?(/^UC[A-Za-z0-9_-]+$/) ? id : nil
    end

    private def self.extract_handle_channel(url : String) : String?
      match = url.match(%r{youtube\.com/@([^/?]+)}i)
      return unless match
      resolve_handle_to_channel_id(match[1], url)
    end

    private def self.extract_custom_channel(url : String) : String?
      match = url.match(%r{youtube\.com/c/([^/?]+)}i)
      return unless match
      resolve_custom_url_to_channel_id(match[1], url)
    end

    private def self.extract_user_channel(url : String) : String?
      match = url.match(%r{youtube\.com/user/([^/?]+)}i)
      return unless match
      resolve_user_to_channel_id(match[1], url)
    end

    private def self.resolve_channel_id(url : String, config : RequestConfig) : String?
      if url.includes?("/@")
        match = url.match(%r{youtube\.com/@([^/?]+)}i)
        return resolve_handle_to_channel_id(match[1], url, config) if match
      end

      if url.includes?("/c/")
        match = url.match(%r{youtube\.com/c/([^/?]+)}i)
        return resolve_custom_url_to_channel_id(match[1], url, config) if match
      end

      if url.includes?("/user/")
        match = url.match(%r{youtube\.com/user/([^/?]+)}i)
        return resolve_user_to_channel_id(match[1], url, config) if match
      end

      nil
    end

    private def self.resolve_handle_to_channel_id(handle : String, url : String, config : RequestConfig? = nil) : String?
      try_rss_with_params(url, {"slug" => handle}, config || RequestConfig.new)
    end

    private def self.resolve_custom_url_to_channel_id(name : String, url : String, config : RequestConfig? = nil) : String?
      try_rss_with_params(url, {"name" => name}, config || RequestConfig.new)
    end

    private def self.resolve_user_to_channel_id(username : String, url : String, config : RequestConfig? = nil) : String?
      try_rss_with_params(url, {"user" => username}, config || RequestConfig.new)
    end

    private def self.try_rss_with_params(original_url : String, params : Hash(String, String), config : RequestConfig = RequestConfig.new) : String?
      rss_url = "#{YOUTUBE_RSS_BASE}#{params.map { |k, v| "#{k}=#{URI.encode_path(v)}" }.join("&")}"

      http_client = Fetcher::CrestHttpClient.new(config)
      response = http_client.get(rss_url, Fetcher::CrestHttpClient.build_headers(::HTTP::Headers.new))

      return unless response.status_code == 200

      channel_id = extract_channel_id_from_feed(response.body)
      return channel_id if channel_id && channel_id.starts_with?("UC")
      nil
    rescue
      nil
    end

    private def self.extract_channel_id_from_feed(body : String) : String?
      if match = body.match(/<yt:channelId>UC[^<]+<\/yt:channelId>/i)
        match[0].gsub(/<\/?yt:channelId>/i, "")
      elsif match = body.match(/yt:channelId="(UC[^"]+)"/i)
        match[1]
      end
    end

    private def self.resolve_channel_id_from_page(url : String, config : RequestConfig) : String?
      http_client = Fetcher::CrestHttpClient.new(config)
      response = http_client.get(url, Fetcher::CrestHttpClient.build_headers(::HTTP::Headers.new))

      return unless response.status_code == 200

      extract_channel_id_from_html(response.body)
    rescue
      nil
    end

    private def self.extract_channel_id_from_html(html : String) : String?
      if match = html.match(/"channelId":"(UC[^"]+)"/i)
        return match[1]
      end

      if match = html.match(/<link rel="canonical" href="https:\/\/www\.youtube\.com\/channel\/(UC[^"]+)"/i)
        return match[1]
      end

      if match = html.match(/["']externalId["']\s*:\s*["'](UC[^"']+)["']/i)
        return match[1]
      end

      nil
    end
  end
end
