require "xml"
require "./entry"
require "./result"
require "./time_parser"
require "./author"
require "./attachment"

module Fetcher
  # Streaming RSS/Atom parser using XML::Reader
  class StreamingRSSParser
    def parse_entries(reader : XML::Reader, limit : Int32) : Array(Entry)
      entries = [] of Entry

      # Determine if it's RSS or Atom based on root element
      is_rss = false
      is_atom = false

      while reader.read && (reader.node_type == :element || reader.node_type == :end_element)
        if reader.node_type == :element
          case reader.name
          when "rss", "RDF"
            is_rss = true
            break
          when "feed"
            is_atom = true
            break
          end
        end
      end

      # Reset reader to beginning
      reader = XML::Reader.new(reader.to_s)

      if is_rss
        parse_rss_streaming(reader, limit, entries)
      elsif is_atom
        parse_atom_streaming(reader, limit, entries)
      end

      entries
    end

    private def parse_rss_streaming(reader : XML::Reader, limit : Int32, entries : Array(Entry))
      while reader.read && entries.size < limit
        if reader.node_type == :element && reader.name == "item"
          entry = parse_rss_item_streaming(reader)
          entries << entry if entry
        end
      end
    end

    private def parse_atom_streaming(reader : XML::Reader, limit : Int32, entries : Array(Entry))
      while reader.read && entries.size < limit
        if reader.node_type == :element && reader.name == "entry"
          entry = parse_atom_entry_streaming(reader)
          entries << entry if entry
        end
      end
    end

    private def parse_rss_item_streaming(reader : XML::Reader) : Entry?
      state = {
        title:       "",
        link:        "",
        pub_date:    "",
        content:     "",
        description: "",
        author:      "",
        categories:  [] of String,
        attachments: [] of Attachment,
      }

      depth = 0
      while reader.read
        case reader.node_type
        when :element
          depth += 1
          process_rss_element(reader, reader.name, state)
        when :end_element
          depth -= 1
          break if depth < 0 && reader.name == "item"
        end
      end

      build_rss_entry(state)
    rescue
      nil
    end

    private def process_rss_element(reader : XML::Reader, element_name : String, state : Hash(Symbol, String | Array(String) | Array(Attachment)))
      case element_name
      when "title"
        state[:title] = read_text_content(reader)
      when "link"
        state[:link] = read_text_content(reader)
      when "pubDate", "dc:date", "date"
        state[:pub_date] = read_text_content(reader)
      when "content:encoded"
        state[:content] = read_text_content(reader)
      when "description"
        state[:description] = read_text_content(reader)
      when "dc:creator"
        state[:author] = read_text_content(reader)
      when "category"
        category = read_text_content(reader)
        state[:categories].as(Array(String)) << category unless category.empty?
      when "enclosure"
        attachment = parse_enclosure_attributes(reader)
        state[:attachments].as(Array(Attachment)) << attachment if attachment
      end
    end

    private def build_rss_entry(state : Hash(Symbol, String | Array(String) | Array(Attachment))) : Entry?
      final_content = state[:content].as(String).presence || state[:description].as(String)

      Entry.create(
        title: Entry.sanitize_title(state[:title].as(String)),
        url: HTMLUtils.sanitize_link(state[:link].as(String)),
        source_type: SourceType::RSS,
        content: final_content.strip,
        author: state[:author].as(String).presence,
        published_at: TimeParser.parse(state[:pub_date].as(String)),
        categories: state[:categories].as(Array(String)),
        attachments: state[:attachments].as(Array(Attachment))
      )
    rescue
      nil
    end

    private def parse_atom_entry_streaming(reader : XML::Reader) : Entry?
      state = {
        title:       "",
        link:        "",
        pub_date:    "",
        content:     "",
        summary:     "",
        author_name: "",
        author_uri:  "",
        categories:  [] of String,
      }

      depth = 0
      while reader.read
        case reader.node_type
        when :element
          depth += 1
          process_atom_element(reader, state)
        when :end_element
          depth -= 1
          break if depth < 0 && reader.name == "entry"
        end
      end

      build_atom_entry(state)
    rescue
      nil
    end

    private def process_atom_element(reader : XML::Reader, state : Hash(Symbol, String | Array(String))) : Nil
      case reader.name
      when "title"
        state[:title] = read_text_content(reader)
      when "link"
        href = reader["href"]?
        rel = reader["rel"]?
        if href && (!rel || rel == "alternate")
          state[:link] = href
        end
      when "published", "updated"
        state[:pub_date] = read_text_content(reader)
      when "content"
        state[:content] = read_text_content(reader)
      when "summary"
        state[:summary] = read_text_content(reader)
      when "author"
        parse_atom_author(reader, state)
      when "category"
        term = reader["term"]?
        if term
          (state[:categories].as(Array(String))) << term
        end
      end
    end

    private def parse_atom_author(reader : XML::Reader, state : Hash(Symbol, String | Array(String))) : Nil
      author_depth = 0
      while reader.read
        case reader.node_type
        when :element
          author_depth += 1
          case reader.name
          when "name"
            state[:author_name] = read_text_content(reader)
          when "uri"
            state[:author_uri] = read_text_content(reader)
          end
        when :end_element
          author_depth -= 1
          break if author_depth < 0 && reader.name == "author"
        end
      end
    end

    private def build_atom_entry(state : Hash(Symbol, String | Array(String))) : Entry
      # Use content if available, otherwise summary
      final_content = state[:content].as(String).presence || state[:summary].as(String)

      Entry.create(
        title: Entry.sanitize_title(state[:title].as(String)),
        url: HTMLUtils.sanitize_link(state[:link].as(String)),
        source_type: SourceType::Atom,
        content: final_content.strip,
        author: state[:author_name].as(String).presence,
        author_url: state[:author_uri].as(String).presence,
        published_at: TimeParser.parse(state[:pub_date].as(String)),
        categories: state[:categories].as(Array(String))
      )
    end

    private def read_text_content(reader : XML::Reader) : String
      if reader.node_type == :element && reader.empty_element?
        return ""
      end

      text = ""
      depth = 0
      while reader.read
        case reader.node_type
        when :text, :cdata
          text += reader.value
        when :element
          depth += 1
        when :end_element
          depth -= 1
          break if depth < 0
        end
      end
      text
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
