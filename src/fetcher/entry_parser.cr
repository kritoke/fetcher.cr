require "./entry"
require "./result"

module Fetcher
  record FeedMetadata,
    site_link : String? = nil,
    favicon : String? = nil,
    feed_title : String? = nil,
    feed_description : String? = nil,
    feed_language : String? = nil,
    feed_authors : Array(Author) = [] of Author do
    def to_result(entries : Array(Entry), etag : String? = nil, last_modified : String? = nil) : Result
      Result.builder
        .entries(entries)
        .etag(etag)
        .last_modified(last_modified)
        .site_link(site_link)
        .favicon(favicon)
        .feed_title(feed_title)
        .feed_description(feed_description)
        .feed_language(feed_language)
        .feed_authors(feed_authors)
        .build
    end

    EMPTY = new
  end

  alias RSSFeedMetadata = FeedMetadata

  abstract class EntryParser
    abstract def parse_entries(data : String, limit : Int32) : Array(Entry)
    abstract def parse_feed_metadata(data : String) : FeedMetadata
  end
end
