require "xml"
require "./entry"
require "./result"
require "./time_parser"
require "./author"
require "./attachment"
require "./link_resolver"
require "./xml_text_reader"

module Fetcher
  class StreamingRSSParser
    def parse_entries(reader : XML::Reader, limit : Int32) : Array(Entry)
      entries = [] of Entry

      while reader.read && entries.size < limit
        if reader.node_type == XML::Reader::Type::ELEMENT
          case reader.name
          when "item"
            entry = parse_rss_item_streaming(reader)
            entries << entry if entry
          when "entry"
            entry = parse_atom_entry_streaming(reader)
            entries << entry if entry
          end
        end
      end

      entries
    end

    def parse_single_entry(reader : XML::Reader) : Entry?
      case reader.name
      when "item"  then parse_rss_item_streaming(reader)
      when "entry" then parse_atom_entry_streaming(reader)
      end
    end

    private def parse_rss_item_streaming(reader : XML::Reader) : Entry?
      title = ""
      link = ""
      pub_date_str = ""
      content = ""
      description = ""
      author = ""
      categories = [] of String
      attachments = [] of Attachment
      comments_link = ""

      item_depth = reader.depth
      while reader.read
        case reader.node_type
        when XML::Reader::Type::ELEMENT
          case reader.name
          when "title"                      then title = read_text_content(reader)
          when "link"                       then link = read_text_content(reader)
          when "pubDate", "dc:date", "date" then pub_date_str = read_text_content(reader)
          when "content:encoded"            then content = read_text_content(reader)
          when "description"                then description = read_text_content(reader)
          when "dc:creator"                 then author = read_text_content(reader)
          when "category"
            cat = read_text_content(reader)
            categories << cat unless cat.empty?
          when "enclosure"
            attachment = parse_enclosure_attributes(reader)
            attachments << attachment if attachment
          when "comments" then comments_link = read_text_content(reader)
          end
        when XML::Reader::Type::END_ELEMENT
          break if reader.depth == item_depth && reader.name == "item"
        end
      end

      final_content = content.presence || description

      link_data = LinkResolver.resolve_from_url(link)
      final_comment_url = link_data.comment_url || comments_link.presence

      Entry.create(
        title: Entry.sanitize_title(title),
        url: HTMLUtils.sanitize_link(link),
        source_type: SourceType::RSS,
        content: final_content.strip,
        author: author.presence,
        published_at: TimeParser.normalize(TimeParser.parse(pub_date_str)),
        categories: categories,
        attachments: attachments,
        comment_url: final_comment_url,
        commentary_url: link_data.commentary_url,
        is_discussion_url: link_data.is_discussion_url
      )
    rescue ex
      ::Log.for("fetcher.streaming").warn { "Failed to parse RSS item: #{ex.class} - #{ex.message}" }
      nil
    end

    private def parse_atom_entry_streaming(reader : XML::Reader) : Entry?
      title = ""
      link = ""
      published_str = ""
      content = ""
      summary = ""
      author_name = ""
      author_uri = ""
      categories = [] of String

      entry_depth = reader.depth
      while reader.read
        case reader.node_type
        when XML::Reader::Type::ELEMENT
          case reader.name
          when "title"
            title = read_text_content(reader)
          when "link"
            href = reader["href"]?
            rel = reader["rel"]?
            if href && (!rel || rel == "alternate")
              link = href
            end
            read_text_content(reader)
          when "published", "updated"
            published_str = read_text_content(reader)
          when "content"
            content = read_text_content(reader)
          when "summary"
            summary = read_text_content(reader)
          when "author"
            author_name, author_uri = read_author(reader)
          when "category"
            term = reader["term"]?
            categories << term if term
            read_text_content(reader)
          end
        when XML::Reader::Type::END_ELEMENT
          break if reader.depth == entry_depth && reader.name == "entry"
        end
      end

      final_content = content.presence || summary

      link_data = LinkResolver.resolve_from_url(link)

      Entry.create(
        title: Entry.sanitize_title(title),
        url: HTMLUtils.sanitize_link(link),
        source_type: SourceType::Atom,
        content: final_content.strip,
        author: author_name.presence,
        author_url: author_uri.presence,
        published_at: TimeParser.normalize(TimeParser.parse(published_str)),
        categories: categories,
        comment_url: link_data.comment_url,
        commentary_url: link_data.commentary_url,
        is_discussion_url: link_data.is_discussion_url
      )
    rescue ex
      ::Log.for("fetcher.streaming").warn { "Failed to parse Atom entry: #{ex.class} - #{ex.message}" }
      nil
    end

    private def read_author(reader : XML::Reader) : {String, String}
      name = ""
      uri = ""
      while reader.read
        case reader.node_type
        when XML::Reader::Type::ELEMENT
          case reader.name
          when "name" then name = read_text_content(reader)
          when "uri"  then uri = read_text_content(reader)
          end
        when XML::Reader::Type::END_ELEMENT
          break if reader.name == "author"
        end
      end
      {name, uri}
    end

    private def read_text_content(reader : XML::Reader) : String
      XMLTextReader.read_text_content(reader)
    end

    private def parse_enclosure_attributes(reader : XML::Reader) : Attachment?
      url = reader["url"]?
      type = reader["type"]?
      length_str = reader["length"]?

      return unless url && type

      length = length_str.try(&.to_i64?)

      Attachment.new(
        url: url,
        mime_type: type,
        size_in_bytes: length
      )
    end
  end
end
