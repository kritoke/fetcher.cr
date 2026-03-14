require "xml"
require "./entry"
require "./result"
require "./time_parser"
require "./author" 
require "./attachment"
require "./html_utils"

module Fetcher
  # Simple working XML streaming parser
  class SimpleXMLStreamingParser
    def initialize(@limit : Int32 = 100)
    end

    def parse_entries(io : IO, limit : Int32? = nil) : Array(Entry)
      actual_limit = limit || @limit
      reader = XML::Reader.new(io)
      
      entries = [] of Entry
      is_in_item = false
      current_entry_data = nil
      
      while reader.read && entries.size < actual_limit
        case reader.node_type
        when :element
          if reader.name == "item"
            is_in_item = true
            current_entry_data = {
              :title => "",
              :link => "",
              :pub_date => "",
              :description => "",
              :content => ""
            }
          elsif is_in_item && current_entry_data
            # Handle item elements - read their content
            element_name = reader.name
            element_content = read_element_content(reader)
            
            case element_name
            when "title"
              current_entry_data[:title] = element_content
            when "link"  
              current_entry_data[:link] = element_content
            when "pubDate", "dc:date"
              current_entry_data[:pub_date] = element_content
            when "description"
              current_entry_data[:description] = element_content
            when "content:encoded"
              current_entry_data[:content] = element_content
            end
          end
        when :end_element
          if reader.name == "item" && current_entry_data
            # Create entry
            final_content = current_entry_data[:content].presence || current_entry_data[:description]
            entry = Entry.create(
              title: Entry.sanitize_title(current_entry_data[:title]),
              url: HTMLUtils.sanitize_link(current_entry_data[:link]),
              source_type: SourceType::RSS,
              content: final_content.strip,
              published_at: TimeParser.parse(current_entry_data[:pub_date]),
              author: nil,
              categories: [] of String,
              attachments: [] of Attachment
            )
            entries << entry
            is_in_item = false
            current_entry_data = nil
          end
        end
      end
      
      entries
    end

    private def read_element_content(reader : XML::Reader) : String
      if reader.empty_element?
        return ""
      end
      
      content = ""
      depth = 0
      
      while reader.read
        case reader.node_type
        when :text, :cdata
          content += reader.value
        when :element
          depth += 1
          # Skip nested elements by reading until their closing tag
          while reader.read
            case reader.node_type
            when :end_element
              break
            end
          end
        when :end_element
          break
        end
      end
      
      content
    end
  end
end
