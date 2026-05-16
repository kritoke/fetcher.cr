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

    # Builder for creating success results with many optional fields
    class Builder
      @entries : Array(Entry) = [] of Entry
      @etag : String?
      @last_modified : String?
      @site_link : String?
      @favicon : String?
      @feed_title : String?
      @feed_description : String?
      @feed_language : String?
      @feed_authors : Array(Author) = [] of Author

      def entries(value : Array(Entry)) : self
        @entries = value
        self
      end

      def etag(value : String?) : self
        @etag = value
        self
      end

      def last_modified(value : String?) : self
        @last_modified = value
        self
      end

      def site_link(value : String?) : self
        @site_link = value
        self
      end

      def favicon(value : String?) : self
        @favicon = value
        self
      end

      def feed_title(value : String?) : self
        @feed_title = value
        self
      end

      def feed_description(value : String?) : self
        @feed_description = value
        self
      end

      def feed_language(value : String?) : self
        @feed_language = value
        self
      end

      def feed_authors(value : Array(Author)) : self
        @feed_authors = value
        self
      end

      def build : Result
        Result.new(
          entries: @entries,
          etag: @etag,
          last_modified: @last_modified,
          site_link: @site_link,
          favicon: @favicon,
          error: nil,
          feed_title: @feed_title,
          feed_description: @feed_description,
          feed_language: @feed_language,
          feed_authors: @feed_authors
        )
      end
    end

    # Creates a success result with essential fields only.
    # For optional metadata (site_link, favicon, feed_title, etc.), use Builder instead:
    #
    #   Result.builder
    #     .entries(entries)
    #     .etag(etag)
    #     .site_link("https://example.com")
    #     .favicon("https://example.com/favicon.ico")
    #     .build
    #
    def self.success(entries : Array(Entry), etag : String? = nil, last_modified : String? = nil) : Result
      new(entries: entries, etag: etag, last_modified: last_modified,
        site_link: nil, favicon: nil, error: nil,
        feed_title: nil, feed_description: nil,
        feed_language: nil, feed_authors: [] of Author)
    end

    def self.builder : Builder
      Builder.new
    end

    # Test helper for creating results with site_link (used by specs)
    def self.with_site_link(entries : Array(Entry), site_link : String?) : Result
      builder.entries(entries).site_link(site_link).build
    end

    def success? : Bool
      error.nil?
    end

    def error_message : String?
      error.try(&.message)
    end
  end
end
