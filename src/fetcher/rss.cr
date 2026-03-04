require "xml"
require "html"
require "./entry"
require "./result"
require "./retry"
require "./http_client"
require "./time_parser"
require "./author"
require "./attachment"

module Fetcher
  module RSS
    MAX_FEED_SIZE = 5 * 1024 * 1024

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Result
      Fetcher.with_retry do
        perform_fetch(url, headers, limit, config)
      end
    end

    private def self.perform_fetch(url : String, headers : ::HTTP::Headers, limit : Int32, config : RequestConfig) : Result
      response = HTTPClient.fetch(url, headers, config)

      case response.status_code
      when 304
        Result.success(
          entries: [] of Entry,
          etag: response.headers["ETag"]?,
          last_modified: response.headers["Last-Modified"]?
        )
      when 200..299
        parse_feed(response.body, url, limit)
      when 500..599
        raise RetriableError.new("Server error: #{response.status_code}")
      else
        Fetcher.error_result(ErrorKind::HTTPError, "HTTP #{response.status_code}", response.status_code)
      end
    rescue ex : IO::TimeoutError
      raise RetriableError.new("Timeout: #{ex.message}")
    rescue ex : HTTPClient::DNSError
      raise RetriableError.new("DNS error: #{ex.message}")
    rescue ex
      if Fetcher.transient_error?(ex)
        raise RetriableError.new(ex.message || "Unknown error")
      end
      Fetcher.error_result(ErrorKind::Unknown, "#{ex.class}: #{ex.message}")
    end

    private def self.parse_feed(body : String, url : String, limit : Int32) : Result
      return Fetcher.error_result(ErrorKind::InvalidFormat, "Feed too large (>5MB)") if body.bytesize > MAX_FEED_SIZE

      begin
        xml = XML.parse(body, options: XML::ParserOptions::RECOVER | XML::ParserOptions::NOENT)

        return Fetcher.error_result(ErrorKind::InvalidFormat, "No root element") unless xml.root

        rss = parse_rss(xml, limit)
        return rss unless rss.entries.empty?

        atom = parse_atom(xml, limit)
        return atom unless atom.entries.empty?

        Fetcher.error_result(ErrorKind::InvalidFormat, "Unsupported feed format")
      rescue ex : XML::Error
        Fetcher.error_result(ErrorKind::InvalidFormat, "XML parsing error: #{ex.message}")
      rescue ex
        Fetcher.error_result(ErrorKind::Unknown, "Error: #{ex.class} - #{ex.message}")
      end
    end

    private def self.parse_rss(xml : XML::Node, limit : Int32) : Result
      site_link = "#"
      entries = [] of Entry
      feed_title = ""
      feed_description = ""
      feed_language = ""

      is_rdf = xml.root.try(&.name) == "RDF"
      channel = xml.xpath_node("//*[local-name()='channel']")

      if channel
        site_link = resolve_rss_site_link(channel)
        feed_title = channel.xpath_node("./*[local-name()='title']").try(&.text).try(&.strip) || ""
        feed_description = channel.xpath_node("./*[local-name()='description']").try(&.text).try(&.strip) || ""
        feed_language = channel.xpath_node("./*[local-name()='language']").try(&.text).try(&.strip) || ""

        item_nodes = is_rdf ? xml.xpath_nodes("//*[local-name()='item']") : channel.xpath_nodes("./*[local-name()='item']")
        item_nodes.each do |node|
          entries << parse_rss_item(node)
          break if entries.size >= limit
        end
      end

      favicon = xml.xpath_node("//*[local-name()='channel']/*[local-name()='image']/*[local-name()='url']").try(&.text)

      Result.success(
        entries: entries,
        site_link: site_link,
        favicon: favicon,
        feed_title: feed_title.presence,
        feed_description: feed_description.presence,
        feed_language: feed_language.presence
      )
    end

    private def self.resolve_rss_site_link(channel : XML::Node) : String
      links = channel.xpath_nodes("./*[local-name()='link']")
      site_link_node = links.find do |node|
        node["rel"]? != "self" && (node.text.presence || node["href"]?)
      end || links.first?

      return "#" unless site_link_node
      link = site_link_node["href"]? || site_link_node.text
      link.strip.presence || "#"
    end

    private def self.parse_rss_item(node : XML::Node) : Entry
      title_node = node.xpath_node("./*[local-name()='title']").try(&.text)
      title = Entry.sanitize_title(title_node)

      link = HTMLUtils.sanitize_link(node.xpath_node("./*[local-name()='link']").try(&.text))

      pub_date_str = node.xpath_node("./*[local-name()='pubDate']").try(&.text) ||
                     node.xpath_node("./*[local-name()='dc:date']").try(&.text) ||
                     node.xpath_node("./*[local-name()='date']").try(&.text)
      pub_date = TimeParser.parse(pub_date_str, TimeParser::RSS_FORMATS)

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

    private def self.parse_atom(xml : XML::Node, limit : Int32) : Result
      entries = [] of Entry

      feed_node = xml.xpath_node("//*[local-name()='feed']")
      return Fetcher.error_result(ErrorKind::InvalidFormat, "No feed element") unless feed_node

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

      feed_node.xpath_nodes("./*[local-name()='entry']").each do |node|
        entries << parse_atom_entry(node)
        break if entries.size >= limit
      end

      favicon = feed_node.xpath_node("./*[local-name()='icon']").try(&.text) ||
                feed_node.xpath_node("./*[local-name()='logo']").try(&.text)

      Result.success(
        entries: entries,
        site_link: site_link,
        favicon: favicon,
        feed_title: feed_title.presence,
        feed_description: subtitle.presence,
        feed_language: feed_language.presence,
        feed_authors: feed_authors
      )
    end

    private def self.parse_atom_entry(node : XML::Node) : Entry
      title_node = node.xpath_node("./*[local-name()='title']").try(&.text)
      title = Entry.sanitize_title(title_node)

      link = extract_atom_link(node)

      published_str = node.xpath_node("./*[local-name()='published']").try(&.text) ||
                      node.xpath_node("./*[local-name()='updated']").try(&.text)
      pub_date = TimeParser.parse(published_str, TimeParser::ATOM_FORMATS)

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

    private def self.extract_atom_link(node : XML::Node) : String
      link_node = node.xpath_node("./*[local-name()='link'][@rel='alternate' and (not(@type) or starts-with(@type,'text/html'))]") ||
                  node.xpath_node("./*[local-name()='link'][@rel='alternate']") ||
                  node.xpath_node("./*[local-name()='link'][@href]") ||
                  node.xpath_node("./*[local-name()='link']")
      link_node.try(&.[]?("href")).try(&.strip).presence ||
        link_node.try(&.text).try(&.strip).presence || "#"
    end

    private def self.extract_atom_content(node : XML::Node) : String
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
