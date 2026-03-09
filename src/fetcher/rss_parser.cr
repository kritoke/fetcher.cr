require "xml"
require "./entry"
require "./result"
require "./entry_parser"
require "./time_parser"
require "./author"
require "./attachment"
require "./safe_feed_processor"

module Fetcher
  # RSS and Atom feed parser implementation
  class RSSParser < EntryParser
    def parse_entries(data : String, limit : Int32) : Array(Entry)
      xml = parse_xml(data)
      return [] of Entry unless xml.root

      rss_entries = parse_rss(xml, limit)
      return rss_entries unless rss_entries.empty?

      atom_entries = parse_atom(xml, limit)
      return atom_entries unless atom_entries.empty?

      [] of Entry
    end

    def parse_feed_metadata(data : String) : NamedTuple(
      site_link: String?,
      favicon: String?,
      feed_title: String?,
      feed_description: String?,
      feed_language: String?,
      feed_authors: Array(Author))
      xml = parse_xml(data)
      return {site_link: nil, favicon: nil, feed_title: nil, feed_description: nil, feed_language: nil, feed_authors: [] of Author} unless xml.root

      rss_metadata = parse_rss_metadata(xml)
      return rss_metadata unless rss_metadata[:site_link].nil? && rss_metadata[:feed_title].nil?

      atom_metadata = parse_atom_metadata(xml)
      return atom_metadata unless atom_metadata[:site_link].nil? && atom_metadata[:feed_title].nil?

      {site_link: nil, favicon: nil, feed_title: nil, feed_description: nil, feed_language: nil, feed_authors: [] of Author}
    end

    private def parse_xml(data : String) : XML::Document
      XML.parse(data, options: XML::ParserOptions::RECOVER |
                               XML::ParserOptions::NOENT |
                               XML::ParserOptions::NONET)
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

    private def parse_rss_metadata(xml : XML::Node) : NamedTuple(
      site_link: String?,
      favicon: String?,
      feed_title: String?,
      feed_description: String?,
      feed_language: String?,
      feed_authors: Array(Author))
      site_link = "#"
      feed_title = ""
      feed_description = ""
      feed_language = ""

      channel = xml.xpath_node("//*[local-name()='channel']")
      if channel
        site_link = resolve_rss_site_link(channel)
        feed_title = channel.xpath_node("./*[local-name()='title']").try(&.text).try(&.strip) || ""
        feed_description = channel.xpath_node("./*[local-name()='description']").try(&.text).try(&.strip) || ""
        feed_language = channel.xpath_node("./*[local-name()='language']").try(&.text).try(&.strip) || ""
      end

      favicon = xml.xpath_node("//*[local-name()='channel']/*[local-name()='image']/*[local-name()='url']").try(&.text)

      {
        site_link:        site_link,
        favicon:          favicon,
        feed_title:       feed_title.presence,
        feed_description: feed_description.presence,
        feed_language:    feed_language.presence,
        feed_authors:     [] of Author,
      }
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
      title_node = node.xpath_node("./*[local-name()='title']").try(&.text)
      title = Entry.sanitize_title(title_node)

      link = HTMLUtils.sanitize_link(node.xpath_node("./*[local-name()='link']").try(&.text))

      pub_date_str = node.xpath_node("./*[local-name()='pubDate']").try(&.text) ||
                     node.xpath_node("./*[local-name()='dc:date']").try(&.text) ||
                     node.xpath_node("./*[local-name()='date']").try(&.text)
      pub_date = TimeParser.parse(pub_date_str)

      content_encoded = node.xpath_node("./*[local-name()='encoded']").try(&.text)
      description = node.xpath_node("./*[local-name()='description']").try(&.text)
      content = content_encoded || description || ""

      dc_creator = node.xpath_node("./*[local-name()='creator']").try(&.text)
      author = dc_creator.try(&.strip).presence

      categories = node.xpath_nodes("./*[local-name()='category']").compact_map do |cat|
        cat.text.try(&.strip).presence
      end

      attachments = node.xpath_nodes("./*[local-name()='enclosure']").compact_map do |enc|
        url = enc["url"]?
        type = enc["type"]?
        length = enc["length"]?.try(&.to_i64)
        next unless url && type
        Attachment.new(url: url, mime_type: type, size_in_bytes: length)
      end

      Entry.create(
        title: title,
        url: link,
        source_type: SourceType::RSS,
        content: content.strip,
        author: author,
        published_at: pub_date,
        categories: categories,
        attachments: attachments
      )
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

    private def parse_atom_metadata(xml : XML::Node) : NamedTuple(
      site_link: String?,
      favicon: String?,
      feed_title: String?,
      feed_description: String?,
      feed_language: String?,
      feed_authors: Array(Author))
      feed_node = xml.xpath_node("//*[local-name()='feed']")
      return {site_link: nil, favicon: nil, feed_title: nil, feed_description: nil, feed_language: nil, feed_authors: [] of Author} unless feed_node

      alt = feed_node.xpath_node("./*[local-name()='link'][@rel='alternate' and (not(@type) or starts-with(@type,'text/html'))]") ||
            feed_node.xpath_node("./*[local-name()='link'][@rel='alternate']") ||
            feed_node.xpath_node("./*[local-name()='link'][not(@rel) and @href]") ||
            feed_node.xpath_node("./*[local-name()='link'][@href]")
      site_link = alt.try(&.[]?("href")).try(&.strip) || alt.try(&.text).try(&.strip)

      feed_title = feed_node.xpath_node("./*[local-name()='title']").try(&.text).try(&.strip) || ""
      subtitle = feed_node.xpath_node("./*[local-name()='subtitle']").try(&.text).try(&.strip) || ""
      feed_language = feed_node.xpath_node("./*[local-name()='xml:lang']").try(&.text).try(&.strip) || ""

      feed_authors = feed_node.xpath_nodes("./*[local-name()='author']").compact_map do |author_node|
        name = author_node.xpath_node("./*[local-name()='name']").try(&.text).try(&.strip)
        uri = author_node.xpath_node("./*[local-name()='uri']").try(&.text).try(&.strip)
        next unless name
        Author.new(name: name, url: uri, avatar: nil)
      end

      favicon = feed_node.xpath_node("./*[local-name()='icon']").try(&.text) ||
                feed_node.xpath_node("./*[local-name()='logo']").try(&.text)

      {
        site_link:        site_link,
        favicon:          favicon,
        feed_title:       feed_title.presence,
        feed_description: subtitle.presence,
        feed_language:    feed_language.presence,
        feed_authors:     feed_authors,
      }
    end

    private def parse_atom_entry(node : XML::Node) : Entry
      title_node = node.xpath_node("./*[local-name()='title']").try(&.text)
      title = Entry.sanitize_title(title_node)

      link = extract_atom_link(node)

      published_str = node.xpath_node("./*[local-name()='published']").try(&.text) ||
                      node.xpath_node("./*[local-name()='updated']").try(&.text)
      pub_date = TimeParser.parse(published_str)

      content = extract_atom_content(node)

      author_node = node.xpath_node("./*[local-name()='author']")
      author = author_node.try(&.xpath_node("./*[local-name()='name']").try(&.text)).try(&.strip).presence
      author_url = author_node.try(&.xpath_node("./*[local-name()='uri']").try(&.text)).try(&.strip).presence

      categories = node.xpath_nodes("./*[local-name()='category']").compact_map do |cat|
        cat["term"]?.try(&.strip).presence
      end

      Entry.create(
        title: title,
        url: link,
        source_type: SourceType::Atom,
        content: content.strip,
        author: author,
        author_url: author_url,
        published_at: pub_date,
        categories: categories
      )
    end

    private def extract_atom_link(node : XML::Node) : String
      link_node = node.xpath_node("./*[local-name()='link'][@rel='alternate' and (not(@type) or starts-with(@type,'text/html'))]") ||
                  node.xpath_node("./*[local-name()='link'][@rel='alternate']") ||
                  node.xpath_node("./*[local-name()='link'][@href]") ||
                  node.xpath_node("./*[local-name()='link']")
      link_node.try(&.[]?("href")).try(&.strip).presence ||
        link_node.try(&.text).try(&.strip).presence || "#"
    end

    private def extract_atom_content(node : XML::Node) : String
      content_node = node.xpath_node("./*[local-name()='content']")
      summary_node = node.xpath_node("./*[local-name()='summary']")
      content_type = content_node.try(&.[]?("type")) || "text"

      case content_type
      when "html", "xhtml" then content_node.try(&.text) || ""
      when "text"          then content_node.try(&.text) || ""
      else                      summary_node.try(&.text) || ""
      end
    end
  end
end
