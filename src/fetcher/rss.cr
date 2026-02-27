require "xml"
require "html"
require "./entry"
require "./result"
require "./retry"
require "./http_client"

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
        Result.new(
          entries: [] of Entry,
          etag: response.headers["ETag"]?,
          last_modified: response.headers["Last-Modified"]?,
          site_link: nil,
          favicon: nil,
          error_message: nil
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

      Result.new(
        entries: entries,
        etag: nil,
        last_modified: nil,
        site_link: site_link,
        favicon: favicon,
        error_message: nil
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
      title = node.xpath_node("./*[local-name()='title']").try(&.text).try(&.strip)
      title = HTML.unescape(title) if title
      title = "Untitled" if title.nil? || title.empty?

      link = node.xpath_node("./*[local-name()='link']").try(&.text) || "#"

      pub_date_str = node.xpath_node("./*[local-name()='pubDate']").try(&.text) ||
                     node.xpath_node("./*[local-name()='dc:date']").try(&.text) ||
                     node.xpath_node("./*[local-name()='date']").try(&.text)
      pub_date = parse_time(pub_date_str)

      Entry.new(title, link, "", nil, pub_date, "rss", nil)
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

      Result.new(
        entries: entries,
        etag: nil,
        last_modified: nil,
        site_link: site_link,
        favicon: favicon,
        error_message: nil
      )
    end

    private def self.parse_atom_entry(node : XML::Node) : Entry
      title = node.xpath_node("./*[local-name()='title']").try(&.text).try(&.strip)
      title = HTML.unescape(title) if title
      title = "Untitled" if title.nil? || title.empty?

      link_node = node.xpath_node("./*[local-name()='link'][@rel='alternate' and (not(@type) or starts-with(@type,'text/html'))]") ||
                  node.xpath_node("./*[local-name()='link'][@rel='alternate']") ||
                  node.xpath_node("./*[local-name()='link'][@href]") ||
                  node.xpath_node("./*[local-name()='link']")
      link = link_node.try(&.[]?("href")) || link_node.try(&.text).try(&.strip) || "#"

      published_str = node.xpath_node("./*[local-name()='published']").try(&.text) ||
                      node.xpath_node("./*[local-name()='updated']").try(&.text)
      pub_date = parse_time(published_str)

      Entry.new(title, link, "", nil, pub_date, "atom", nil)
    end

    private def self.parse_time(time_str : String?) : Time?
      return unless time_str

      formats = [
        "%a, %d %b %Y %H:%M:%S %z",
        "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d",
      ]

      formats.each do |fmt|
        begin
          return Time.parse(time_str.strip, fmt, Time::Location::UTC)
        rescue
        end
      end

      begin
        return Time.parse_iso8601(time_str.strip)
      rescue
      end

      nil
    end
  end
end
