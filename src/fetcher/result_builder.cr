require "./result"
require "./entry"

module Fetcher
  # Builder for creating structured Result instances
  class ResultBuilder
    @entries : Array(Entry) = [] of Entry
    @etag : String? = nil
    @last_modified : String? = nil
    @site_link : String? = nil
    @favicon : String? = nil
    @error : Error? = nil
    @feed_title : String? = nil
    @feed_description : String? = nil
    @feed_language : String? = nil
    @feed_authors : Array(Author) = [] of Author

    def entries(entries : Array(Entry)) : self
      @entries = entries
      self
    end

    def etag(etag : String?) : self
      @etag = etag
      self
    end

    def last_modified(last_modified : String?) : self
      @last_modified = last_modified
      self
    end

    def site_link(site_link : String?) : self
      @site_link = site_link
      self
    end

    def favicon(favicon : String?) : self
      @favicon = favicon
      self
    end

    def error(error : Error?) : self
      @error = error
      self
    end

    def feed_title(feed_title : String?) : self
      @feed_title = feed_title
      self
    end

    def feed_description(feed_description : String?) : self
      @feed_description = feed_description
      self
    end

    def feed_language(feed_language : String?) : self
      @feed_language = feed_language
      self
    end

    def feed_authors(feed_authors : Array(Author)) : self
      @feed_authors = feed_authors
      self
    end

    def build : Result
      Result.new(
        entries: @entries,
        etag: @etag,
        last_modified: @last_modified,
        site_link: @site_link,
        favicon: @favicon,
        error: @error,
        feed_title: @feed_title,
        feed_description: @feed_description,
        feed_language: @feed_language,
        feed_authors: @feed_authors
      )
    end

    def self.success(
      entries : Array(Entry),
      etag : String? = nil,
      last_modified : String? = nil,
      site_link : String? = nil,
      favicon : String? = nil,
      feed_title : String? = nil,
      feed_description : String? = nil,
      feed_language : String? = nil,
      feed_authors : Array(Author) = [] of Author,
    ) : Result
      new
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

    def self.error(error : Error) : Result
      new.error(error).build
    end
  end
end
