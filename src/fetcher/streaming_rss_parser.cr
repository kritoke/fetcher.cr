require "xml"
require "./entry"
require "./result"
require "./time_parser"
require "./author"
require "./attachment"
require "./link_resolver"

module Fetcher
  # Streaming RSS/Atom parser using XML::Reader
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

    # Parse a single entry from the current reader position
    # Reader must be positioned at an "item" or "entry" element
    def parse_single_entry(reader : XML::Reader) : Entry?
      case reader.name
      when "item"  then parse_rss_item_streaming(reader)
      when "entry" then parse_atom_entry_streaming(reader)
      end
    end

    private def parse_rss_streaming(reader : XML::Reader, limit : Int32, entries : Array(Entry))
      while reader.read && entries.size < limit
        if reader.node_type == XML::Reader::Type::ELEMENT && reader.name == "item"
          entry = parse_rss_item_streaming(reader)
          entries << entry if entry
        end
      end
    end

    private def parse_atom_streaming(reader : XML::Reader, limit : Int32, entries : Array(Entry))
      while reader.read && entries.size < limit
        if reader.node_type == XML::Reader::Type::ELEMENT && reader.name == "entry"
          entry = parse_atom_entry_streaming(reader)
          entries << entry if entry
        end
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

      depth = 0
      while reader.read
        case reader.node_type
        when XML::Reader::Type::ELEMENT
          depth += 1
          case reader.name
          when "title"
            title = read_text_content(reader)
          when "link"
            link = read_text_content(reader)
          when "pubDate", "dc:date", "date"
            pub_date_str = read_text_content(reader)
          when "content:encoded"
            content = read_text_content(reader)
          when "description"
            description = read_text_content(reader)
          when "dc:creator"
            author = read_text_content(reader)
          when "category"
            category = read_text_content(reader)
            categories << category unless category.empty?
          when "enclosure"
            attachment = parse_enclosure_attributes(reader)
            attachments << attachment if attachment
          when "comments"
            comments_link = read_text_content(reader)
          end
        when XML::Reader::Type::END_ELEMENT
          depth -= 1
          break if depth == 0 && reader.name == "item"
        end
      end

      # Use content:encoded if available, otherwise description
      final_content = content.presence || description

      link_data = LinkResolver.resolve_from_url(link)
      final_comment_url = link_data.comment_url || comments_link.presence

      Entry.create(
        title: Entry.sanitize_title(title),
        url: HTMLUtils.sanitize_link(link),
        source_type: SourceType::RSS,
        content: final_content.strip,
        author: author.presence,
        published_at: TimeParser.parse(pub_date_str),
        categories: categories,
        attachments: attachments,
        comment_url: final_comment_url,
        commentary_url: link_data.commentary_url,
        is_discussion_url: link_data.is_discussion_url
      )
    rescue ex
      ::Log.for("fetcher.streaming").debug { "Failed to parse RSS item: #{ex.class} - #{ex.message}" }
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

      depth = 0
      while reader.read
        case reader.node_type
        when XML::Reader::Type::ELEMENT
          depth += 1
          case reader.name
          when "title"
            title = read_text_content(reader)
          when "link"
            href = reader["href"]?
            rel = reader["rel"]?
            if href && (!rel || rel == "alternate")
              link = href
            end
          when "published", "updated"
            published_str = read_text_content(reader)
          when "content"
            content = read_text_content(reader)
          when "summary"
            summary = read_text_content(reader)
          when "author"
            # Parse nested author element
            author_depth = 0
            while reader.read
              case reader.node_type
              when XML::Reader::Type::ELEMENT
                author_depth += 1
                case reader.name
                when "name"
                  author_name = read_text_content(reader)
                when "uri"
                  author_uri = read_text_content(reader)
                end
              when XML::Reader::Type::END_ELEMENT
                author_depth -= 1
                break if author_depth < 0 && reader.name == "author"
              end
            end
          when "category"
            term = reader["term"]?
            if term
              categories << term
            end
          end
        when XML::Reader::Type::END_ELEMENT
          depth -= 1
          break if depth == 0 && reader.name == "entry"
        end
      end

      # Use content if available, otherwise summary
      final_content = content.presence || summary

      link_data = LinkResolver.resolve_from_url(link)

      Entry.create(
        title: Entry.sanitize_title(title),
        url: HTMLUtils.sanitize_link(link),
        source_type: SourceType::Atom,
        content: final_content.strip,
        author: author_name.presence,
        author_url: author_uri.presence,
        published_at: TimeParser.parse(published_str),
        categories: categories,
        comment_url: link_data.comment_url,
        commentary_url: link_data.commentary_url,
        is_discussion_url: link_data.is_discussion_url
      )
    rescue ex
      ::Log.for("fetcher.streaming").debug { "Failed to parse Atom entry: #{ex.class} - #{ex.message}" }
      nil
    end

    private def read_text_content(reader : XML::Reader) : String
      if reader.node_type == XML::Reader::Type::ELEMENT && reader.empty_element?
        return ""
      end

      builder = String::Builder.new
      depth = 0
      while reader.read
        case reader.node_type
        when XML::Reader::Type::TEXT, XML::Reader::Type::CDATA
          builder << reader.value
        when XML::Reader::Type::ELEMENT
          depth += 1
        when XML::Reader::Type::END_ELEMENT
          depth -= 1
          break if depth < 0
        end
      end
      builder.to_s
    end

    private def parse_enclosure_attributes(reader : XML::Reader) : Attachment?
      url = reader["url"]?
      type = reader["type"]?
      length_str = reader["length"]?

      return unless url && type

      length = length_str.try(&.to_i64)

      Attachment.new(
        url: url,
        mime_type: type,
        size_in_bytes: length
      )
    end
  end
end
