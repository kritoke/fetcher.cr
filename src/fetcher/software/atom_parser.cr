require "xml"
require "../rss_parser"
require "../link_resolver"

module Fetcher
  module Software
    module AtomParser
      def self.try_parse(http_client : CrestHttpClient, atom_url : String, provider : SoftwareProvider, limit : Int32) : Result?
        response = http_client.get(atom_url, headers_for(atom_url))

        return if response.status_code == 404
        return unless (200..299).includes?(response.status_code)

        entries = parse_atom_entries(response.body, provider.source_type, limit)
        return if entries.empty?

        Result.success(
          entries: entries,
          etag: response.headers["ETag"]?,
          last_modified: response.headers["Last-Modified"]?,
          site_link: "#{provider.base_url}/#{provider.repo}",
          favicon: "#{provider.base_url}/favicon.ico"
        )
      rescue ex : OpenSSL::SSL::Error
        raise DNSError.new("#{provider.name} SSL error: #{ex.message}")
      rescue ex : FetchError
        raise ex
      rescue ex
        ::Log.for("fetcher.software").debug { "#{provider.name} atom feed failed: #{ex.class} - #{ex.message}" }
        nil
      end

      def self.parse_atom_entries(body : String, source_type : SourceType, limit : Int32) : Array(Entry)
        parser = RSSParser.new
        entries = parser.parse_entries(body, limit)
        entries.map do |entry|
          version = entry.version || extract_version(entry.title)
          link_data = LinkResolver.resolve_from_url(entry.url)
          Entry.create(
            title: entry.title,
            url: entry.url,
            source_type: source_type,
            content: entry.content,
            content_html: entry.content_html,
            author: entry.author,
            author_url: entry.author_url,
            published_at: entry.published_at,
            categories: entry.categories,
            attachments: entry.attachments,
            version: version,
            comment_url: link_data.comment_url,
            commentary_url: link_data.commentary_url,
            is_discussion_url: link_data.is_discussion_url
          )
        end
      rescue XML::Error
        [] of Entry
      end

      private def self.headers_for(url : String) : ::HTTP::Headers
        Fetcher::CrestHttpClient.build_headers(::HTTP::Headers.new)
      end

      private def self.extract_version(title : String) : String?
        match = title.match(/v?\d+\.\d+(?:\.\d+)?(?:[-._]?\w+)?/)
        match ? match[0] : nil
      end
    end
  end
end
