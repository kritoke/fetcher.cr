require "./entry"
require "./result"
require "./retry"
require "./crest_http_client"
require "./rss"
require "./exceptions"

module Fetcher
  module YouTube
    YOUTUBE_RSS_BASE = "https://www.youtube.com/feeds/videos.xml?channel_id="

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      channel_id = extract_channel_id(url)
      return Fetcher.error_result(ErrorKind::InvalidURL, "Not a valid YouTube channel URL. Only /channel/UC... URLs are supported.") unless channel_id

      rss_url = "#{YOUTUBE_RSS_BASE}#{channel_id}"

      Fetcher.with_retry(config) do
        fetch_youtube(rss_url, channel_id, headers, limit, config)
      end
    end

    def self.parse_youtube_feed(body : String, channel_id : String, limit : Int32 = 100) : Result
      parser = RSSParser.new
      entries = parser.parse_entries(body, limit)
      metadata = parser.parse_feed_metadata(body)

      youtube_entries = entries.map do |entry|
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
          attachments: entry.attachments
        )
      end

      Result.success(
        entries: youtube_entries,
        site_link: "https://www.youtube.com/channel/#{channel_id}",
        favicon: "https://www.youtube.com/favicon.ico",
        feed_title: metadata[:feed_title],
        feed_description: metadata[:feed_description]
      )
    rescue ex
      Fetcher.error_result(ErrorKind::InvalidFormat, "Failed to parse YouTube feed: #{ex.message}")
    end

    private def self.fetch_youtube(rss_url : String, channel_id : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      http_client = Fetcher::CrestHttpClient.new(config)
      response = http_client.get(rss_url, headers)

      case response.status_code
      when 200..299
        parse_youtube_feed(response.body, channel_id, limit)
      when 404
        error = Error.invalid_url("YouTube channel not found", rss_url)
        raise InvalidURLError.new(error.message, error)
      else
        error = Error.http(response.status_code, "HTTP error #{response.status_code}", rss_url)
        raise HTTPError.new(error.message, response.status_code, error)
      end
    rescue ex : FetchError
      raise ex
    rescue ex
      error = Error.unknown("#{ex.class}: #{ex.message}", rss_url)
      Fetcher.error_result(error)
    end

    private def self.extract_channel_id(url : String) : String?
      match = url.match(%r{youtube\.com/channel/([^/?]+)}i)
      match ? match[1] : nil
    end
  end
end
