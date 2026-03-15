require "spec"
require "../../src/fetcher"

describe "Integration Tests - Software" do
  describe "GitHub releases JSON parsing" do
    it "parses valid GitHub releases structure" do
      github_json = <<-JSON
        [
          {
            "tag_name": "v1.0.0",
            "name": "Release 1.0.0",
            "html_url": "https://github.com/test/repo/releases/v1.0.0",
            "published_at": "2024-01-15T10:30:00Z",
            "prerelease": false,
            "draft": false
          }
        ]
        JSON

      releases = Array(JSON::Any).from_json(github_json)
      releases.size.should eq(1)

      release = releases[0]
      release["tag_name"].as_s.should eq("v1.0.0")
      release["prerelease"].as_bool.should be_false
    end

    it "filters out prereleases" do
      github_json = <<-JSON
        [
          {
            "tag_name": "v1.0.0",
            "name": "Stable",
            "prerelease": false,
            "draft": false
          },
          {
            "tag_name": "v1.1.0-beta",
            "name": "Beta",
            "prerelease": true,
            "draft": false
          }
        ]
        JSON

      releases = Array(JSON::Any).from_json(github_json)
      stable = releases.reject { |release| release["prerelease"]?.try(&.as_bool) || release["draft"]?.try(&.as_bool) }
      stable.size.should eq(1)
      stable[0]["tag_name"].as_s.should eq("v1.0.0")
    end

    it "extracts body content from GitHub releases" do
      github_json = %([{"tag_name":"v1.0.0","name":"Release 1.0.0","html_url":"https://github.com/test/repo/releases/v1.0.0","published_at":"2024-01-15T10:30:00Z","body":"## Changes - Fixed bug","prerelease":false,"draft":false}])

      releases = Array(JSON::Any).from_json(github_json)
      release = releases[0]
      body = release["body"]
      body.as_s.should contain("Changes")
    end
  end

  describe "GitLab API JSON parsing" do
    it "parses valid GitLab releases API structure" do
      gitlab_json = %([{"tag_name":"v1.0.0","name":"Release 1.0.0","description":"Release Notes for major release","released_at":"2024-01-15T10:30:00Z","_links":{"self":"https://gitlab.com/test/repo/-/releases/v1.0.0"}}])

      releases = Array(JSON::Any).from_json(gitlab_json)
      releases.size.should eq(1)

      release = releases[0]
      release["tag_name"].as_s.should eq("v1.0.0")
      release["description"].as_s.should contain("Release Notes")
      release["_links"]["self"].as_s.should eq("https://gitlab.com/test/repo/-/releases/v1.0.0")
    end

    it "handles missing optional fields" do
      gitlab_json = %([{"tag_name":"v2.0.0","released_at":"2024-02-01T00:00:00Z"}])

      releases = Array(JSON::Any).from_json(gitlab_json)
      release = releases[0]
      release["name"]?.should be_nil
      release["description"]?.should be_nil
    end
  end

  describe "Codeberg API JSON parsing" do
    it "parses valid Codeberg releases API structure" do
      codeberg_json = %([{"tag_name":"v1.0.0","name":"First Release","body":"Initial release with core features.","html_url":"https://codeberg.org/test/repo/releases/tag/v1.0.0","published_at":"2024-01-15T10:30:00Z"}])

      releases = Array(JSON::Any).from_json(codeberg_json)
      releases.size.should eq(1)

      release = releases[0]
      release["tag_name"].as_s.should eq("v1.0.0")
      release["body"].as_s.should contain("Initial release")
    end
  end

  describe "Software version extraction" do
    it "extracts semantic version patterns" do
      version_patterns = [
        {"v1.2.3", "v1.2.3"},
        {"Release 2.0.0", "2.0.0"},
        {"v1.0.0-beta", "v1.0.0-beta"},
        {"1.0.0", "1.0.0"},
        {"v10.20.30", "v10.20.30"},
      ]

      version_patterns.each do |input, expected|
        match = input.match(/v?\d+\.\d+(?:\.\d+)?(?:[-._]?\w+)?/)
        match.should_not be_nil
         match.as(Regex::MatchData)[0].should eq(expected)
      end
    end

    it "handles titles without versions" do
      non_version_titles = ["Initial Release", "Hello World", "Bug Fixes"]
      non_version_titles.each do |title|
        match = title.match(/v?\d+\.\d+(?:\.\d+)?(?:[-._]?\w+)?/)
        match.should be_nil
      end
    end
  end

  # Our GitLab namespace fix tests
  describe "GitLab Atom feed namespace handling" do
    it "parses namespaced Atom feed entries correctly" do
      # This is the exact issue we fixed - namespace handling
      atom_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Test Release</title>
            <link href="https://example.com/release"/>
            <updated>2024-01-15T10:30:00Z</updated>
          </entry>
        </feed>
        XML

      # Test the actual parsing logic by using the same XPath queries
      xml = XML.parse(atom_xml, options: XML::ParserOptions::RECOVER |
                                         XML::ParserOptions::NOENT |
                                         XML::ParserOptions::NONET)

      # This should find entries (the fix we made)
      entries = xml.xpath_nodes("//*[local-name()='entry']")
      entries.size.should eq(1)

      entry = entries[0]
      title_node = entry.xpath_node("./*[local-name()='title']")
      title = title_node.nil? ? "Untitled" : title_node.text
      title.should eq("Test Release")

      link_node = entry.xpath_node("./*[local-name()='link']")
      link = link_node.try(&.[]?("href")).try(&.strip).presence || ""
      link.should eq("https://example.com/release")
    end

    it "parses Inkscape GitLab releases correctly" do
      # Load fixture data that demonstrates the original problem
      xml_content = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>inkscape releases</title>
          <link href="https://gitlab.com/inkscape/inkscape/-/releases.atom" rel="self" type="application/atom+xml"/>
          <entry>
            <id>https://gitlab.com/inkscape/inkscape/-/releases/INKSCAPE_1_4</id>
            <link href="https://gitlab.com/inkscape/inkscape/-/releases/INKSCAPE_1_4"/>
            <title>INKSCAPE_1_4</title>
            <updated>2024-10-12T21:20:04Z</updated>
            <content></content>
          </entry>
        </feed>
        XML

      xml = XML.parse(xml_content, options: XML::ParserOptions::RECOVER |
                                            XML::ParserOptions::NOENT |
                                            XML::ParserOptions::NONET)

      entries = xml.xpath_nodes("//*[local-name()='entry']")
      entries.size.should eq(1)

      first_entry = entries[0]
      title_node = first_entry.xpath_node("./*[local-name()='title']")
      title = title_node.nil? ? "Untitled" : title_node.text
      title.should eq("INKSCAPE_1_4")

      link_node = first_entry.xpath_node("./*[local-name()='link']")
      link = link_node.try(&.[]?("href")).try(&.strip).presence || ""
      link.should eq("https://gitlab.com/inkscape/inkscape/-/releases/INKSCAPE_1_4")
    end

    it "handles all software platforms consistently" do
      platforms = ["github", "gitlab", "codeberg"]
      platforms.each do |platform|
        atom_xml = <<-XML
          <?xml version="1.0" encoding="UTF-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
              <title>v1.0.0</title>
              <link href="https://#{platform}.com/test/test/releases/tag/v1.0.0"/>
              <updated>2024-01-15T10:30:00Z</updated>
            </entry>
          </feed>
          XML

        xml = XML.parse(atom_xml, options: XML::ParserOptions::RECOVER |
                                           XML::ParserOptions::NOENT |
                                           XML::ParserOptions::NONET)

        entries = xml.xpath_nodes("//*[local-name()='entry']")
        entries.size.should eq(1)

        entry = entries[0]
        title_node = entry.xpath_node("./*[local-name()='title']")
        title = title_node.nil? ? "Untitled" : title_node.text
        title.should eq("v1.0.0")
      end
    end
  end
end
