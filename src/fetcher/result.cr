require "./author"
require "./fetch_error"

module Fetcher
  record Result,
    entries : Array(Entry),
    etag : String?,
    last_modified : String?,
    site_link : String?,
    favicon : String?,
    error : Error? = nil,
    feed_title : String? = nil,
    feed_description : String? = nil,
    feed_language : String? = nil,
    feed_authors : Array(Author) = [] of Author do
    def self.error(err : Error) : Result
      new(entries: [] of Entry, etag: nil, last_modified: nil,
        site_link: nil, favicon: nil, error: err)
    end

    def self.error(kind : ErrorKind, message : String, status_code : Int32? = nil) : Result
      error(Error.new(kind: kind, message: message, status_code: status_code))
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
        site_link: site_link, favicon: favicon, error: nil,
        feed_title: feed_title, feed_description: feed_description,
        feed_language: feed_language, feed_authors: feed_authors)
    end

    def success? : Bool
      error.nil?
    end

    def error_message : String?
      error.try(&.message)
    end
  end
end
