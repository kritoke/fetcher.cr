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
      node.children.find { |c| c.element? && c.name == name }
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

    private def parse_xml(data : String) : XML::Document
      XML.parse(data, options: XML::ParserOptions::RECOVER |
                               XML::ParserOptions::NONET |
                               XML::ParserOptions::NOBLANKS |
                               XML::ParserOptions::NODICT)
    rescue ex : XML::Error
      raise InvalidFormatError.new("XML parsing error: #{ex.message}")
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
      xml.xpath_node("//*[local-name()='channel']/*[local-name()='image']/*[local-name()='url']").try(&.text)
    end

    private def resolve_rss_site_link(channel : XML::Node) : String
      links = channel.xpath_nodes("./*[local-name()='link']")
      site_link_node = links.find do |node|
        node["rel"]? != "self" && (node.text.presence || node["href"]?)
      end || links.first?

      return "#" unless site_link_node
      link = site_link_node["href"]? || site_link_node.text
      link.strip.presence || "#"
    end

    private def parse_rss_item(node : XML::Node) : Entry
      children = node.children.select(&.element?)

      title = Entry.sanitize_title(extract_rss_title(children))
      link = extract_rss_link(children)
      pub_date = extract_rss_pub_date(children)
      content = extract_rss_content(children)
      author = extract_rss_author(children)
      categories = extract_rss_categories(children)
      attachments = extract_rss_attachments(children)
      comments_link = extract_rss_comments_link(children)
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

    private def extract_rss_title(children : Array(XML::Node)) : String?
      children.find { |child| child.name == "title" }.try(&.text).try(&.strip)
    end

    private def extract_rss_link(children : Array(XML::Node)) : String?
      HTMLUtils.sanitize_link(children.find { |child| child.name == "link" }.try(&.text))
    end

    private def extract_rss_pub_date(children : Array(XML::Node)) : Time?
      pub_date_str = children.find { |child| child.name == "pubDate" }.try(&.text) ||
                     children.find { |child| child.name == "dc:date" }.try(&.text) ||
                     children.find { |child| child.name == "date" }.try(&.text)
      TimeParser.parse(pub_date_str)
    end

    private def extract_rss_content(children : Array(XML::Node)) : String
      content_encoded = children.find { |child| child.name == "encoded" }.try(&.text)
      description = children.find { |child| child.name == "description" }.try(&.text)
      content_encoded || description || ""
    end

    private def extract_rss_author(children : Array(XML::Node)) : String?
      children.find { |child| child.name == "creator" }.try(&.text).try(&.strip).presence
    end

    private def extract_rss_categories(children : Array(XML::Node)) : Array(String)
      children.select { |child| child.name == "category" }.compact_map do |cat|
        cat.text.try(&.strip).presence
      end
    end

    private def extract_rss_attachments(children : Array(XML::Node)) : Array(Attachment)
      children.select { |child| child.name == "enclosure" }.compact_map do |enc|
        url = enc["url"]?
        type = enc["type"]?
        length = enc["length"]?.try(&.to_i64?)
        next unless url && type
        Attachment.new(url: url, mime_type: type, size_in_bytes: length)
      end
    end

    private def extract_rss_comments_link(children : Array(XML::Node)) : String?
      children.find { |child| child.name == "comments" }.try(&.text).try(&.strip).presence
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

      title = Entry.sanitize_title(children.find { |child| child.name == "title" }.try(&.text))
      link = extract_atom_link(children)
      pub_date = extract_atom_pub_date(children)
      content = extract_atom_content(children)
      author = extract_atom_author(children)
      author_url = extract_atom_author_url(children)
      categories = extract_atom_categories(children)
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

    private def extract_atom_link(children : Array(XML::Node)) : String
      alt_link = children.find { |child| child.name == "link" && child["rel"]? == "alternate" && (child["type"]?.nil? || child["type"].starts_with?("text/html")) }
      link_node = alt_link ||
                  children.find { |child| child.name == "link" && child["rel"]? == "alternate" } ||
                  children.find { |child| child.name == "link" && child["href"]? } ||
                  children.find { |child| child.name == "link" }
      link_node.try(&.["href"]?).try(&.strip).presence ||
        link_node.try(&.text).try(&.strip).presence || "#"
    end

    private def extract_atom_pub_date(children : Array(XML::Node)) : Time?
      published_str = children.find { |child| child.name == "published" }.try(&.text) ||
                      children.find { |child| child.name == "updated" }.try(&.text)
      TimeParser.parse(published_str)
    end

    private def extract_atom_content(children : Array(XML::Node)) : String
      content_node = children.find { |child| child.name == "content" }
      summary_node = children.find { |child| child.name == "summary" }

      content_node.try(&.text) || summary_node.try(&.text) || ""
    end

    private def extract_atom_author(children : Array(XML::Node)) : String?
      author_node = children.find { |child| child.name == "author" }
      author_node.try(&.children.find { |child| child.name == "name" }).try(&.text).try(&.strip).presence
    end

    private def extract_atom_author_url(children : Array(XML::Node)) : String?
      author_node = children.find { |child| child.name == "author" }
      author_node.try(&.children.find { |child| child.name == "uri" }).try(&.text).try(&.strip).presence
    end

    private def extract_atom_categories(children : Array(XML::Node)) : Array(String)
      children.select { |child| child.name == "category" }.compact_map do |cat|
        cat["term"]?.try(&.strip).presence
      end
    end
  end
end
