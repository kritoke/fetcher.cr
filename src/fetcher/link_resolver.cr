module Fetcher
  module LinkResolver
    record LinkData,
      comment_url : String? = nil,
      commentary_url : String? = nil,
      is_discussion_url : Bool = false

    def self.resolve(node : XML::Node, main_url : String) : LinkData
      comment_url : String? = nil
      commentary_url : String? = nil

      node.xpath_nodes("./*[local-name()='link']").each do |link|
        rel = link["rel"]?
        href = link["href"]?.try(&.strip).presence
        next unless href

        case rel
        when "replies", "comments"
          comment_url ||= href
        when "related"
          commentary_url ||= href
        when "alternate"
        end
      end

      is_discussion = discussion_url?(main_url)

      if is_discussion && comment_url.nil?
        comment_url = main_url
      end

      LinkData.new(
        comment_url: comment_url,
        commentary_url: commentary_url,
        is_discussion_url: is_discussion
      )
    end

    def self.resolve_from_url(url : String) : LinkData
      is_discussion = discussion_url?(url)

      comment_url = is_discussion ? url : nil

      LinkData.new(
        comment_url: comment_url,
        commentary_url: nil,
        is_discussion_url: is_discussion
      )
    end

    DISCUSSION_PATHS = {"/comments/", "/item?id=", "/s/", "/discuss", "/r/"}

    private def self.discussion_url?(url : String) : Bool
      return false if url.empty? || url == "#"

      lower = url.downcase
      DISCUSSION_PATHS.any? { |path| lower.includes?(path) }
    end
  end
end
