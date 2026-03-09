require "./entry"
require "./result"

module Fetcher
  # Base interface for all feed entry parsers
  abstract class EntryParser
    abstract def parse_entries(data : String, limit : Int32) : Array(Entry)
    abstract def parse_feed_metadata(data : String) : NamedTuple(
      site_link: String?,
      favicon: String?,
      feed_title: String?,
      feed_description: String?,
      feed_language: String?,
      feed_authors: Array(Author))
  end
end
