require "xml"

module Fetcher
  # Generic XML node helpers used across feed parsers. Kept module-level
  # rather than tied to any one parser so other XML consumers
  # (e.g. AtomParser subclasses, JSON feed XML adapters) can `include`
  # the same utilities without pulling in the full RSS parser.
  module XMLHelper
    # Extract text content from an xpath result with optional stripping.
    def xpath_text(node : XML::Node, path : String) : String?
      node.xpath_node(path).try(&.text).try(&.strip).presence
    end

    # Find first element child by name.
    def find_child(node : XML::Node, name : String) : XML::Node?
      node.children.find { |child| child.element? && child.name == name }
    end

    # Find element by name and get attribute.
    def find_attr(node : XML::Node, name : String, attr : String) : String?
      find_child(node, name).try(&.[attr]?).try(&.strip).presence
    end

    # Find <link> element with optional rel/type filtering.
    def find_link(children : Array(XML::Node), rel : String? = nil, type : String? = nil) : XML::Node?
      children.find do |child|
        next unless child.name == "link" && child["href"]?
        next if rel && child["rel"]? != rel
        next if type && !child["type"]?.nil? && !child["type"].starts_with?(type)
        true
      end
    end

    # Extract href from link node, falling back to text content.
    def extract_href(node : XML::Node?) : String?
      node.try(&.["href"]).try(&.strip).presence || node.try(&.text).try(&.strip).presence || "#"
    end
  end
end