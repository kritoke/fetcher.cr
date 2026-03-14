require "json"
require "./entry"
require "./result"
require "./time_parser"

module Fetcher
  # Simple working JSON streaming parser
  class SimpleJSONStreamingParser
    def initialize(@limit : Int32 = 100)
    end

    def parse_entries(io : IO, limit : Int32? = nil) : Array(Entry)
      actual_limit = limit || @limit
      
      # For now, use the existing JSON parsing but with streaming approach
      # This is a placeholder until full streaming implementation is ready
      begin
        json_data = JSON.parse(io)
        
        # Detect if it's Reddit or JSON Feed
        data_hash = json_data.as_h?
        if data_hash && data_hash.has_key?("data")
          data_data = data_hash["data"].as_h?
          if data_data && data_data.has_key?("children")
            # Reddit format
            return parse_reddit_entries(json_data, actual_limit)
          end
        end
        
        if data_hash && data_hash.has_key?("version") && 
           data_hash["version"].as_s.includes?("jsonfeed")
          # JSON Feed format
          return parse_json_feed_entries(json_data, actual_limit)
        end
        
        # Unknown format
        return [] of Entry
      rescue JSON::ParseException
        return [] of Entry
      end
    end

    private def parse_reddit_entries(json_data : JSON::Any, limit : Int32) : Array(Entry)
      entries = [] of Entry
      children = json_data["data"]["children"]?.as_a?
      
      return entries unless children
      
      children.first(limit).each do |child|
        entry = parse_reddit_post_from_json(child)
        entries << entry if entry
      end
      
      entries
    end

    private def parse_json_feed_entries(json_data : JSON::Any, limit : Int32) : Array(Entry)
      entries = [] of Entry
      items = json_data["items"]?.as_a?
      
      return entries unless items
      
      items.first(limit).each do |item|
        entry = parse_json_feed_item_from_json(item)
        entries << entry if entry
      end
      
      entries
    end

    private def parse_reddit_post_from_json(child : JSON::Any) : Entry?
      post_data = child["data"]? || return nil
      
      title = post_data["title"]?.try(&.as_s) || "Untitled"
      post_url = post_data["url"]?.try(&.as_s) || ""
      permalink = post_data["permalink"]?.try(&.as_s) || ""
      created_utc = post_data["created_utc"]?.try(&.as_f) || 0.0
      is_self = post_data["is_self"]?.try(&.as_bool) || false
      
      link = resolve_reddit_link(post_url, permalink, is_self)
      pub_date = created_utc > 0 ? Time.unix(created_utc.to_i64) : nil
      
      Entry.create(
        title: title,
        url: link,
        source_type: SourceType::Reddit,
        published_at: pub_date
      )
    end

    private def parse_json_feed_item_from_json(item : JSON::Any) : Entry?
      id = item["id"]?.try(&.as_s) || ""
      url = item["url"]?.try(&.as_s) || id
      title = item["title"]?.try(&.as_s) || "Untitled"
      content_html = item["content_html"]?.try(&.as_s) || ""
      content_text = item["content_text"]?.try(&.as_s) || ""
      date_published = item["date_published"]?.try(&.as_s) || ""
      
      content = content_html.presence || content_text.presence || ""
      pub_date = date_published.empty? ? nil : TimeParser.parse(date_published)
      
      Entry.create(
        title: title,
        url: url,
        source_type: SourceType::JSONFeed,
        content: content,
        published_at: pub_date
      )
    end

    private def resolve_reddit_link(post_url : String, permalink : String, is_self : Bool) : String
      is_self || post_url.empty? ? "https://www.reddit.com#{permalink}" : post_url
    end
  end
end
