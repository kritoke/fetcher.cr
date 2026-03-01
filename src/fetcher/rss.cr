require "xml"
require "html"
require "./entry"
require "./result"
require "./retry"
require "./http_client"
require "./time_parser"

module Fetcher
  module RSS
    MAX_FEED_SIZE = 5 * 1024 * 1024

    def self.pull(url : String, headers : ::HTTP::Headers, limit : Int32 = 100) : Result
      Fetcher.with_retry do
        perform_fetch(url, headers, limit)
      end
    end

    private def self.perform_fetch(url : String, headers : ::HTTP::Headers, limit : Int32) : Result
      response = HTTPClient.fetch(url, headers)

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
        Fetcher.error_result("HTTP #{response.status_code}")
      end
    rescue ex : IO::TimeoutError
      raise RetriableError.new("Timeout: #{ex.message}")
    rescue ex
      if Fetcher.transient_error?(ex)
        raise RetriableError.new(ex.message || "Unknown error")
      end
      Fetcher.error_result("#{ex.class}: #{ex.message}")
    end

    private def self.parse_feed(body : String, url : String, limit : Int32) : Result
      return Fetcher.error_result("Feed too large (>5MB)") if body.bytesize > MAX_FEED_SIZE

      begin
        xml = XML.parse(body, options: XML::ParserOptions::RECOVER | XML::ParserOptions::NOENT)

        return Fetcher.error_result("No root element") unless xml.root

        rss = parse_rss(xml, limit)
        return rss unless rss.entries.empty?

        atom = parse_atom(xml, limit)
        return atom unless atom.entries.empty?

        Fetcher.error_result("Unsupported feed format")
      rescue ex : XML::Error
        Fetcher.error_result("XML parsing error: #{ex.message}")
      rescue ex
        Fetcher.error_result("Error: #{ex.class} - #{ex.message}")
      end
    end

    private def self.parse_rss(xml : XML::Node, limit : Int32) : Result
      site_link = "#"
      entries = [] of Entry

      is_rdf = xml.root.try(&.name) == "RDF"

      if is_rdf
        if channel = xml.xpath_node("//*[local-name()='channel']")
          site_link = resolve_rss_site_link(channel)
        end
        xml.xpath_nodes("//*[local-name()='item']").each do |node|
          entries << parse_rss_item(node)
          break if entries.size >= limit
        end
      else
        if channel = xml.xpath_node("//*[local-name()='channel']")
          site_link = resolve_rss_site_link(channel)
          channel.xpath_nodes("./*[local-name()='item']").each do |node|
            entries << parse_rss_item(node)
            break if entries.size >= limit
          end
        end
      end

      favicon = xml.xpath_node("//*[local-name()='channel']/*[local-name()='image']/*[local-name()='url']").try(&.text)

      Result.success(
        entries: entries,
        site_link: site_link,
        favicon: favicon
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

      Entry.create(title: title, url: link, source_type: "rss", published_at: pub_date)
    end

    private def self.parse_atom(xml : XML::Node, limit : Int32) : Result
      entries = [] of Entry

      feed_node = xml.xpath_node("//*[local-name()='feed']")
      return Fetcher.error_result("No feed element") unless feed_node

      alt = feed_node.xpath_node("./*[local-name()='link'][@rel='alternate' and (not(@type) or starts-with(@type,'text/html'))]") ||
            feed_node.xpath_node("./*[local-name()='link'][@rel='alternate']") ||
            feed_node.xpath_node("./*[local-name()='link'][not(@rel) and @href]") ||
            feed_node.xpath_node("./*[local-name()='link'][@href]")
      site_link = alt.try(&.[]?("href")).try(&.strip) || alt.try(&.text).try(&.strip)

      feed_node.xpath_nodes("./*[local-name()='entry']").each do |node|
        entries << parse_atom_entry(node)
        break if entries.size >= limit
      end

      favicon = feed_node.xpath_node("./*[local-name()='icon']").try(&.text) ||
                feed_node.xpath_node("./*[local-name()='logo']").try(&.text)

      Result.success(
        entries: entries,
        site_link: site_link,
        favicon: favicon
      )
    end

    private def self.parse_atom_entry(node : XML::Node) : Entry
      title_node = node.xpath_node("./*[local-name()='title']").try(&.text)
      title = Entry.sanitize_title(title_node)

      link_node = node.xpath_node("./*[local-name()='link'][@rel='alternate' and (not(@type) or starts-with(@type,'text/html'))]") ||
                  node.xpath_node("./*[local-name()='link'][@rel='alternate']") ||
                  node.xpath_node("./*[local-name()='link'][@href]") ||
                  node.xpath_node("./*[local-name()='link']")
      link = link_node.try(&.[]?("href")).try(&.strip).presence ||
             link_node.try(&.text).try(&.strip).presence || "#"

      published_str = node.xpath_node("./*[local-name()='published']").try(&.text) ||
                      node.xpath_node("./*[local-name()='updated']").try(&.text)
      pub_date = TimeParser.parse(published_str, TimeParser::ATOM_FORMATS)

      Entry.create(title: title, url: link, source_type: "atom", published_at: pub_date)
    end
  end
end
