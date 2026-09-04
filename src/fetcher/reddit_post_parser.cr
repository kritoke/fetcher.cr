require "json"
require "log"
require "./entry"
require "./exceptions"
require "./link_resolver"
require "./source_type"
require "./time_parser"

module Fetcher
  # DOM-style JSON-to-Entry adapter for Reddit API responses.
  # Owns the response-shape parsing and nothing else (no HTTP, cache,
  # OAuth, or status handling). Lives next to `reddit_json_parser.cr`,
  # which does the streaming variant.
  module RedditPostParser
    # Build the array of `Entry` from a Reddit API JSON body, capped at
    # `limit`. Returns `[]` for shapes we don't recognize, raises
    # `InvalidFormatError` for malformed JSON.
    def self.parse(body : String, limit : Int32) : Array(Entry)
      parsed = JSON.parse(body)
      children = extract_children(parsed)
      return [] of Entry if children.nil?

      children.first(limit).compact_map { |child| build_entry(child) }
    rescue JSON::ParseException
      raise InvalidFormatError.new("Failed to parse Reddit JSON response")
    end

    # Pull the `children` array out of either a single listing object
    # or an array-wrapped listing, returning nil for unrecognized shapes.
    def self.extract_children(parsed : JSON::Any) : Array(JSON::Any)?
      listing = parsed.as_a?.try &.[]?(0).try &.["data"]? || parsed["data"]?
      listing.try(&.["children"]?).try(&.as_a?)
    rescue ex : KeyError | TypeCastError | IndexError
      ::Log.for("fetcher.reddit").warn { "Unexpected JSON structure in Reddit response: #{ex.message}" }
      nil
    end

    def self.build_entry(child : JSON::Any) : Entry?
      post_data = extract_post_data(child)
      return unless post_data

      Entry.create(
        title: post_data.title,
        url: post_data.url,
        source_type: SourceType::Reddit,
        published_at: post_data.pub_date,
        is_discussion_url: post_data.link_data.is_discussion_url,
        comment_url: post_data.link_data.comment_url || post_data.discussion_url
      )
    end

    def self.extract_post_data(child : JSON::Any) : PostData?
      post = child["data"]?
      return unless post

      discussion_url = build_discussion_url(extract_permalink(post))
      effective_url = determine_effective_url(post, discussion_url)

      PostData.new(
        title: extract_title(post),
        url: effective_url,
        discussion_url: discussion_url,
        pub_date: extract_pub_date(post),
        link_data: LinkResolver.resolve_from_url(effective_url)
      )
    end

    def self.extract_title(post : JSON::Any) : String
      post["title"]?.try(&.as_s) || "Untitled"
    end

    def self.extract_permalink(post : JSON::Any) : String
      post["permalink"]?.try(&.as_s) || ""
    end

    def self.build_discussion_url(permalink : String) : String
      "https://www.reddit.com#{permalink}"
    end

    def self.determine_effective_url(post : JSON::Any, discussion_url : String) : String
      is_self = post["is_self"]?.try(&.as_bool) || false
      post_url = post["url"]?.try(&.as_s) || ""
      is_self || post_url.empty? ? discussion_url : post_url
    end

    def self.extract_pub_date(post : JSON::Any) : Time?
      created_utc = post["created_utc"]?.try(&.as_f) || 0.0
      created_utc > 0 ? TimeParser.normalize(Time.unix(created_utc.to_i64)) : nil
    end

    record PostData,
      title : String,
      url : String,
      discussion_url : String,
      pub_date : Time?,
      link_data : LinkResolver::LinkData
  end
end