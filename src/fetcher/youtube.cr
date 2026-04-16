require "./entry"
require "./result"
require "./retry"
require "./crest_http_client"
require "./rss"
require "./exceptions"
require "./error_handler"
require "./link_resolver"

module Fetcher
  module YouTube
    YOUTUBE_RSS_BASE = "https://www.youtube.com/feeds/videos.xml?channel_id="

    YOUTUBE_CACHE_TTL = 5.minutes

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      channel_id = extract_channel(url)
      return Fetcher.error_result(ErrorKind::InvalidURL, "Not a valid YouTube channel URL. Only /channel/UC... URLs are supported.") unless channel_id

      cache_key = "youtube:#{channel_id}:#{limit}"

      if config.cache_config.enabled
        if cached = config.cache.get(cache_key)
          return cached
        end
      end

      rss_url = "#{YOUTUBE_RSS_BASE}#{channel_id}"

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

      Result.success(
        entries: youtube_entries,
        site_link: "https://www.youtube.com/channel/#{channel_id}",
        favicon: "https://www.youtube.com/favicon.ico",
        feed_title: metadata.feed_title,
        feed_description: metadata.feed_description
      )
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
    rescue ex : Exception
      ErrorHandler.handle_network_error(ex, rss_url)
    end

    private def self.extract_channel(url : String) : String?
      match = url.match(%r{youtube\.com/channel/([^/?]+)}i)
      return unless match
      id = match[1]
      id if id.starts_with?("UC") && id.matches?(/^UC[A-Za-z0-9_-]+$/)
    end
  end
end
