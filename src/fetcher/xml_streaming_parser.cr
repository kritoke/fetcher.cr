require "xml"
require "./entry"
require "./result"  
require "./time_parser"
require "./author"
require "./attachment"
require "./html_utils"
require "./rss_parser"

module Fetcher
  # XML streaming parser using XML::Reader with lazy iterator pattern
  class XMLStreamingParser
    def initialize(@limit : Int32 = 100)
      @entries_parsed = 0
    end

    # Parse XML feed and return lazy iterator
    def parse(io : IO) : XMLStreamingIterator
      XMLStreamingIterator.new(io, @limit)
    end

    # Parse XML feed and return array (for compatibility)
    def parse_entries(io : IO, limit : Int32? = nil) : Array(Entry)
      actual_limit = limit || @limit
      parse(io).to_a(actual_limit)
    end
  end

  # Lazy iterator for XML streaming parser
  class XMLStreamingIterator < EntryIterator
    def initialize(@io : IO, @limit : Int32)
      super()
      @reader = XML::Reader.new(@io)
      @feed_metadata_extracted = false
      @entries_parsed = 0
    end

    protected def next_entry : Entry?
      return nil if @entries_parsed >= @limit

      while @reader.read
        if @reader.node_type == :element
          case @reader.name
          when "item", "entry"
            # Extract complete item/entry XML
            item_xml = @reader.read_outer_xml
            
            # Parse using existing RSSParser logic
            begin
              doc = XML.parse(item_xml)
              entry_node = doc.root
              if entry_node
                if @reader.name == "item"
                  entry = RSSParser.new.parse_rss_item(entry_node)
                else
                  entry = RSSParser.new.parse_atom_entry(entry_node)
                end
                
                if entry
                  @entries_parsed += 1
                  return entry
                end
              end
            rescue ex : XML::Error
              # Skip malformed items, continue processing
              next
            end
          when "rss", "RDF", "feed"
            # Extract feed metadata on first encounter
            unless @feed_metadata_extracted
              extract_feed_metadata(@reader)
              @feed_metadata_extracted = true
            end
          end
        end
      end

      nil
    end

    private def extract_feed_metadata(reader : XML::Reader)
      # This is a placeholder - feed metadata extraction will be implemented later
      # For now, we focus on entry parsing
    end
  end
end
