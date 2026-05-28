require "xml"
require "./entry"
require "./result"
require "./entry_parser"
require "./time_parser"
require "./author"
require "./attachment"
require "./safe_feed_processor"
require "./link_resolver"

module Fetcher
  # Helper module for XML node operations to reduce message chains
  module XMLHelper
    # Extract text content from an xpath result with optional stripping
    def xpath_text(node : XML::Node, path : String) : String?
      node.xpath_node(path).try(&.text).try(&.strip).presence
    end

    # Find first element child by name
    def find_child(node : XML::Node, name : String) : XML::Node?
      node.children.find { |child| child.element? && child.name == name }
    end

    # Find element by name and get attribute
    def find_attr(node : XML::Node, name : String, attr : String) : String?
      find_child(node, name).try(&.[attr]?).try(&.strip).presence
    end

    # Find link with optional rel and type filtering
    def find_link(children : Array(XML::Node), rel : String? = nil, type : String? = nil) : XML::Node?
      children.find do |child|
        next unless child.name == "link" && child["href"]?
        next if rel && child["rel"]? != rel
        next if type && !child["type"]?.nil? && !child["type"].starts_with?(type)
        true
      end
    end

    # Extract href from link node
    def extract_href(node : XML::Node?) : String?
      node.try(&.["href"]).try(&.strip).presence || node.try(&.text).try(&.strip).presence || "#"
    end
  end

  EMPTY_FEED_METADATA = FeedMetadata.new

  # RSS and Atom feed parser implementation
  class RSSParser < EntryParser
    include XMLHelper

    def parse_entries(data : String, limit : Int32) : Array(Entry)
      xml = parse_xml(data)
      parse_entries(xml, limit)
    end

    def parse_entries(xml : XML::Document, limit : Int32) : Array(Entry)
      return [] of Entry unless xml.root

      rss_entries = parse_rss(xml, limit)
      return rss_entries unless rss_entries.empty?

      atom_entries = parse_atom(xml, limit)
      return atom_entries unless atom_entries.empty?

      [] of Entry
    end

    def parse_feed_metadata(data : String) : FeedMetadata
      xml = parse_xml(data)
      parse_feed_metadata(xml)
    end

    def parse_feed_metadata(xml : XML::Document) : FeedMetadata
      return EMPTY_FEED_METADATA unless xml.root

      rss_metadata = parse_rss_metadata(xml)
      return rss_metadata unless rss_metadata.site_link.nil? && rss_metadata.feed_title.nil?

      atom_metadata = parse_atom_metadata(xml)
      return atom_metadata unless atom_metadata.site_link.nil? && atom_metadata.feed_title.nil?

      EMPTY_FEED_METADATA
    end

    def parse_all(data : String, limit : Int32) : Tuple(Array(Entry), FeedMetadata)
      xml = parse_xml(data)
      entries = parse_entries(xml, limit)
      metadata = parse_feed_metadata(xml)
      {entries, metadata}
    end

    def parse_all(xml : XML::Document, limit : Int32) : Tuple(Array(Entry), FeedMetadata)
      entries = parse_entries(xml, limit)
      metadata = parse_feed_metadata(xml)
      {entries, metadata}
    end

    def parse_xml_document(data : String) : XML::Document
      parse_xml(data)
    end

    # Maximum entity definitions allowed before suspecting entity expansion attack
    MAX_ENTITY_DEFINITIONS = 10

    private def parse_xml(data : String) : XML::Document
      check_entity_expansion_risk(data)

      XML.parse(data, options: XML::ParserOptions::RECOVER |
                               XML::ParserOptions::NONET |
                               XML::ParserOptions::NOBLANKS |
                               XML::ParserOptions::NODICT)
    rescue ex : XML::Error
      raise InvalidFormatError.new("XML parsing error: #{ex.message}")
    end

    # Detect patterns that could cause exponential entity expansion (billion laughs / XML bomb)
    # Reject DOCTYPE with internal subset entirely, as well-formed feeds don't need them.
    private def check_entity_expansion_risk(content : String) : Nil
      # Use uppercase for case-insensitive comparison
      upper = content.upcase

      # Reject DOCTYPE with internal subset - common vector for entity expansion attacks
      if upper.includes?("<!DOCTYPE") && upper.includes?("[")
        raise InvalidFormatError.new("DOCTYPE with internal subset not allowed (entity expansion risk)")
      end

      # Check for parameter entities which are also dangerous
      if upper.scan(/<!ENTITY\s+%/i).size > 0
        raise InvalidFormatError.new("Parameter entity declarations not allowed")
      end

      # Check for external entity declarations (SYSTEM keyword)
      if upper.includes?("<!ENTITY") && upper.includes?("SYSTEM")
        raise InvalidFormatError.new("External entity declarations not allowed")
      end

      # Check entity definition count
      entity_count = count_entity_definitions(content)
      if entity_count > MAX_ENTITY_DEFINITIONS
        raise InvalidFormatError.new("Too many entity definitions (#{entity_count})")
      end
    rescue ex : InvalidFormatError
      raise ex  # Re-raise our own errors
    rescue
      # Ignore unexpected errors during the check (e.g., regex failures)
    end

    private def count_entity_definitions(content : String) : Int32
      count = 0
      content.scan(/<!ENTITY\s+\w+\s+[^>]*>/i) { count += 1 }
      count
    end

    private def parse_rss(xml : XML::Node, limit : Int32) : Array(Entry)
      entries = [] of Entry

      is_rdf = xml.root.try(&.name) == "RDF"
      channel = xml.xpath_node("//*[local-name()='channel']")

      if channel
        item_nodes = is_rdf ? xml.xpath_nodes("//*[local-name()='item']") : channel.xpath_nodes("./*[local-name()='item']")
        item_nodes.each do |node|
          entries << parse_rss_item(node)
          break if entries.size >= limit
        end
      end

      entries
    end

    private def parse_rss_metadata(xml : XML::Node) : FeedMetadata
      channel = xml.xpath_node("//*[local-name()='channel']")
      return EMPTY_FEED_METADATA unless channel

      FeedMetadata.new(
        site_link: resolve_rss_site_link(channel),
        favicon: extract_rss_favicon(xml),
        feed_title: extract_rss_title_text(channel),
        feed_description: extract_rss_description_text(channel),
        feed_language: extract_rss_language(channel),
        feed_authors: [] of Author,
      )
    end

    private def extract_rss_title_text(channel : XML::Node) : String?
      xpath_text(channel, "./*[local-name()='title']")
    end

    private def extract_rss_description_text(channel : XML::Node) : String?
      xpath_text(channel, "./*[local-name()='description']")
    end

    private def extract_rss_language(channel : XML::Node) : String?
      xpath_text(channel, "./*[local-name()='language']")
    end

    private def extract_rss_favicon(xml : XML::Node) : String?
      # Don't extract RSS <image><url> as favicon - it's the channel logo, not a favicon.
      # This is typically 60x60 or larger and not appropriate for use as a favicon.
      nil
    end

    private def resolve_rss_site_link(channel : XML::Node) : String
      links = channel.xpath_nodes("./*[local-name()='link']")
      site_link_node = links.find do |node|
        node["rel"]? != "self" && (node.text.presence || node["href"]?)
      end

      return "#" unless site_link_node
      link = site_link_node["href"]? || site_link_node.text
      link.strip.presence || "#"
    end

    private def parse_rss_item(node : XML::Node) : Entry
      children = node.children.select(&.element?)
      child_map = build_child_map(children)

      title = Entry.sanitize_title(extract_from_map(child_map, "title").try(&.text))
      link = HTMLUtils.sanitize_link(extract_from_map(child_map, "link").try(&.text))
      pub_date = extract_rss_pub_date(child_map)
      content = extract_rss_content(child_map)
      author = extract_from_map(child_map, "creator").try(&.text).try(&.strip).presence
      categories = (child_map["category"]? || [] of XML::Node).compact_map { |cat| cat.text.try(&.strip).presence }
      attachments = extract_rss_attachments(child_map)
      comments_link = extract_from_map(child_map, "comments").try(&.text).try(&.strip).presence
      link_data = LinkResolver.resolve(node, link)

      Entry.create(
        title: title,
        url: link,
        source_type: SourceType::RSS,
        content: content.strip,
        author: author,
        published_at: pub_date,
        categories: categories,
        attachments: attachments,
        comment_url: link_data.comment_url || comments_link,
        commentary_url: link_data.commentary_url,
        is_discussion_url: link_data.is_discussion_url
      )
    end

    # Build a Hash from tag name to child nodes for O(1) lookup
    private def build_child_map(children : Array(XML::Node)) : Hash(String, Array(XML::Node))
      map = {} of String => Array(XML::Node)
      children.each do |child|
        name = child.name
        (map[name] ||= [] of XML::Node) << child
      end
      map
    end

    # Get first matching child from map (returns nil if not found)
    private def extract_from_map(map : Hash(String, Array(XML::Node)), tag : String) : XML::Node?
      map[tag]?.try(&.first?)
    end

    private def extract_rss_pub_date(child_map : Hash(String, Array(XML::Node))) : Time?
      pub_date_str = extract_from_map(child_map, "pubDate").try(&.text) ||
                    extract_from_map(child_map, "dc:date").try(&.text) ||
                    extract_from_map(child_map, "date").try(&.text)
      TimeParser.normalize(TimeParser.parse(pub_date_str)) if pub_date_str
    end

    private def extract_rss_content(child_map : Hash(String, Array(XML::Node))) : String
      content_encoded = extract_from_map(child_map, "encoded").try(&.text)
      description = extract_from_map(child_map, "description").try(&.text)
      content_encoded || description || ""
    end

    private def extract_rss_attachments(child_map : Hash(String, Array(XML::Node))) : Array(Attachment)
      (child_map["enclosure"]? || [] of XML::Node).compact_map do |enc|
        url = enc["url"]?
        type = enc["type"]?
        length = enc["length"]?.try(&.to_i64?)
        next unless url && type
        Attachment.new(url: url, mime_type: type, size_in_bytes: length)
      end
    end

    private def parse_atom(xml : XML::Node, limit : Int32) : Array(Entry)
      entries = [] of Entry

      feed_node = xml.xpath_node("//*[local-name()='feed']")
      return [] of Entry unless feed_node

      feed_node.xpath_nodes("./*[local-name()='entry']").each do |node|
        entries << parse_atom_entry(node)
        break if entries.size >= limit
      end

      entries
    end

    private def parse_atom_metadata(xml : XML::Node) : FeedMetadata
      feed_node = xml.xpath_node("//*[local-name()='feed']")
      return EMPTY_FEED_METADATA unless feed_node

      FeedMetadata.new(
        site_link: extract_atom_site_link(feed_node),
        favicon: extract_atom_favicon(feed_node),
        feed_title: extract_atom_title(feed_node),
        feed_description: extract_atom_subtitle(feed_node),
        feed_language: extract_atom_language(feed_node),
        feed_authors: extract_atom_authors(feed_node),
      )
    end

    private def extract_atom_site_link(feed_node : XML::Node) : String?
      alt = feed_node.xpath_node("./*[local-name()='link'][@rel='alternate' and (not(@type) or starts-with(@type,'text/html'))]") ||
            feed_node.xpath_node("./*[local-name()='link'][@rel='alternate']") ||
            feed_node.xpath_node("./*[local-name()='link'][not(@rel) and @href]") ||
            feed_node.xpath_node("./*[local-name()='link'][@href]")
      alt.try(&.[]?("href")).try(&.strip) || alt.try(&.text).try(&.strip)
    end

    private def extract_atom_title(feed_node : XML::Node) : String?
      feed_node.xpath_node("./*[local-name()='title']").try(&.text).try(&.strip).presence
    end

    private def extract_atom_subtitle(feed_node : XML::Node) : String?
      feed_node.xpath_node("./*[local-name()='subtitle']").try(&.text).try(&.strip).presence
    end

    private def extract_atom_language(feed_node : XML::Node) : String?
      feed_node.xpath_node("./*[local-name()='xml:lang']").try(&.text).try(&.strip).presence
    end

    private def extract_atom_authors(feed_node : XML::Node) : Array(Author)
      feed_node.xpath_nodes("./*[local-name()='author']").compact_map do |author_node|
        name = author_node.xpath_node("./*[local-name()='name']").try(&.text).try(&.strip)
        uri = author_node.xpath_node("./*[local-name()='uri']").try(&.text).try(&.strip)
        next unless name
        Author.new(name: name, url: uri, avatar: nil)
      end
    end

    private def extract_atom_favicon(feed_node : XML::Node) : String?
      feed_node.xpath_node("./*[local-name()='icon']").try(&.text) ||
        feed_node.xpath_node("./*[local-name()='logo']").try(&.text)
    end

    private def parse_atom_entry(node : XML::Node) : Entry
      children = node.children.select(&.element?)
      child_map = build_child_map(children)

      title = Entry.sanitize_title(extract_from_map(child_map, "title").try(&.text))
      link = extract_atom_link(child_map)
      pub_date = extract_atom_pub_date(child_map)
      content = extract_atom_content(child_map)
      author = extract_atom_author(child_map)
      author_url = extract_atom_author_url(child_map)
      categories = (child_map["category"]? || [] of XML::Node).compact_map { |cat| cat["term"]?.try(&.strip).presence }
      link_data = LinkResolver.resolve(node, link)

      Entry.create(
        title: title,
        url: link,
        source_type: SourceType::Atom,
        content: content.strip,
        author: author,
        author_url: author_url,
        published_at: pub_date,
        categories: categories,
        comment_url: link_data.comment_url,
        commentary_url: link_data.commentary_url,
        is_discussion_url: link_data.is_discussion_url
      )
    end

    private def extract_atom_link(child_map : Hash(String, Array(XML::Node))) : String
      links = child_map["link"]? || [] of XML::Node
      alt_link = links.find { |l| l["rel"]? == "alternate" && (l["type"]?.nil? || l["type"].starts_with?("text/html")) }
      link_node = alt_link ||
                  links.find { |l| l["rel"]? == "alternate" } ||
                  links.find { |l| l["href"]? } ||
                  links.first?
      link_node.try(&.["href"]?).try(&.strip).presence ||
        link_node.try(&.text).try(&.strip).presence || "#"
    end

    private def extract_atom_pub_date(child_map : Hash(String, Array(XML::Node))) : Time?
      published_str = extract_from_map(child_map, "published").try(&.text) ||
                      extract_from_map(child_map, "updated").try(&.text)
      TimeParser.normalize(TimeParser.parse(published_str)) if published_str
    end

    private def extract_atom_content(child_map : Hash(String, Array(XML::Node))) : String
      content_node = extract_from_map(child_map, "content")
      summary_node = extract_from_map(child_map, "summary")

      content_node.try(&.text) || summary_node.try(&.text) || ""
    end

    private def extract_atom_author(child_map : Hash(String, Array(XML::Node))) : String?
      author_nodes = child_map["author"]?
      return unless author_nodes
      author_node = author_nodes.first?
      return unless author_node
      author_node.children.find { |c| c.name == "name" }.try(&.text).try(&.strip).presence
    end

    private def extract_atom_author_url(child_map : Hash(String, Array(XML::Node))) : String?
      author_nodes = child_map["author"]?
      return unless author_nodes
      author_node = author_nodes.first?
      return unless author_node
      author_node.children.find { |c| c.name == "uri" }.try(&.text).try(&.strip).presence
    end

    private def extract_atom_categories(children : Array(XML::Node)) : Array(String)
      children.select { |child| child.name == "category" }.compact_map do |cat|
        cat["term"]?.try(&.strip).presence
      end
    end
  end
end
