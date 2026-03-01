require "./author"

module Fetcher
  record Result,
    entries : Array(Entry),
    etag : String?,
    last_modified : String?,
    site_link : String?,
    favicon : String?,
    error_message : String?,
    feed_title : String? = nil,
    feed_description : String? = nil,
    feed_language : String? = nil,
    feed_authors : Array(Author) = [] of Author do
    def self.error(message : String) : Result
      new(entries: [] of Entry, etag: nil, last_modified: nil,
        site_link: nil, favicon: nil, error_message: message)
    end

    def self.success(entries : Array(Entry),
                     etag : String? = nil,
                     last_modified : String? = nil,
                     site_link : String? = nil,
                     favicon : String? = nil,
                     feed_title : String? = nil,
                     feed_description : String? = nil,
                     feed_language : String? = nil,
                     feed_authors : Array(Author) = [] of Author) : Result
      new(entries: entries, etag: etag, last_modified: last_modified,
        site_link: site_link, favicon: favicon, error_message: nil,
        feed_title: feed_title, feed_description: feed_description,
        feed_language: feed_language, feed_authors: feed_authors)
    end
  end
end
