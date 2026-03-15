require "spec"
require "../../src/fetcher"

describe "Integration Tests - JSON Feed" do
  describe "Phase 2: JSON Feed Support" do
    describe "JSON Feed detection" do
      it "detects .json URLs as JSONFeed" do
        Fetcher.detect_driver("https://example.com/feed.json").should eq(Fetcher::DriverType::JSONFeed)
      end

      it "detects /feed.json paths as JSONFeed" do
        Fetcher.detect_driver("https://example.com/blog/feed.json").should eq(Fetcher::DriverType::JSONFeed)
      end

      it "detects /feeds/json paths as JSONFeed" do
        Fetcher.detect_driver("https://example.com/feeds/json").should eq(Fetcher::DriverType::JSONFeed)
      end

      it "does not detect .json without feed pattern as JSONFeed when it's a software URL" do
        Fetcher.detect_driver("https://github.com/user/repo/releases.json").should eq(Fetcher::DriverType::Software)
      end
    end

    describe "JSON Feed parsing" do
      it "parses valid JSON Feed structure" do
        json = <<-JSON
          {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Test Feed",
            "home_page_url": "https://example.com",
            "items": [
              {
                "id": "1",
                "title": "Test Item",
                "url": "https://example.com/item-1",
                "content_text": "Test content"
              }
            ]
          }
          JSON

        parsed = JSON.parse(json)
        version = parsed["version"]?.try(&.as_s)
        title = parsed["title"]?.try(&.as_s)
        items = parsed["items"]?.try(&.as_a)

        version.should eq("https://jsonfeed.org/version/1.1")
        title.should eq("Test Feed")
        items.try(&.size).should eq(1)
      end

      it "extracts content_html over content_text" do
        json = <<-JSON
          {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Test",
            "items": [{
              "id": "1",
              "content_html": "<p>HTML content</p>",
              "content_text": "Text content"
            }]
          }
          JSON

        parsed = JSON.parse(json)
        item = parsed["items"][0]
        content_html = item["content_html"]?.try(&.as_s)
        content_text = item["content_text"]?.try(&.as_s)
        content = content_html || content_text || ""

        content.should eq("<p>HTML content</p>")
      end

      it "extracts authors from item" do
        json = <<-JSON
          {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Test",
            "items": [{
              "id": "1",
              "content_text": "Test",
              "authors": [{"name": "Jane Doe", "url": "https://example.com/jane"}]
            }]
          }
          JSON

        parsed = JSON.parse(json)
        item = parsed["items"][0]
        authors = item["authors"]?.try(&.as_a)
        author_name = authors.try(&.first?).try(&.["name"]?.try(&.as_s))

        author_name.should eq("Jane Doe")
      end

      it "extracts tags as categories" do
        json = <<-JSON
          {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Test",
            "items": [{
              "id": "1",
              "content_text": "Test",
              "tags": ["Ruby", "Crystal"]
            }]
          }
          JSON

        parsed = JSON.parse(json)
        item = parsed["items"][0]
        tags = item["tags"]?.try(&.as_a).try(&.map(&.as_s)) || [] of String

        tags.size.should eq(2)
        tags.should contain("Ruby")
        tags.should contain("Crystal")
      end

      it "extracts attachments" do
        json = <<-JSON
          {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Test",
            "items": [{
              "id": "1",
              "content_text": "Test",
              "attachments": [{
                "url": "https://example.com/file.mp3",
                "mime_type": "audio/mpeg",
                "size_in_bytes": 12345,
                "duration_in_seconds": 3600
              }]
            }]
          }
          JSON

        parsed = JSON.parse(json)
        item = parsed["items"][0]
        attachments = item["attachments"]?.try(&.as_a)

        attachments.try(&.size).should eq(1)
        att = attachments.try(&.first?)
        att.try(&.["url"].as_s).should eq("https://example.com/file.mp3")
        att.try(&.["mime_type"].as_s).should eq("audio/mpeg")
      end

      it "extracts feed-level metadata" do
        json = <<-JSON
          {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Feed Title",
            "home_page_url": "https://example.com",
            "description": "Feed Description",
            "language": "en-US",
            "icon": "https://example.com/icon.png",
            "favicon": "https://example.com/favicon.ico",
            "items": []
          }
          JSON

        parsed = JSON.parse(json)
        title = parsed["title"]?.try(&.as_s)
        home_url = parsed["home_page_url"]?.try(&.as_s)
        description = parsed["description"]?.try(&.as_s)
        language = parsed["language"]?.try(&.as_s)
        favicon = parsed["favicon"]?.try(&.as_s)
        icon = parsed["icon"]?.try(&.as_s)

        title.should eq("Feed Title")
        home_url.should eq("https://example.com")
        description.should eq("Feed Description")
        language.should eq("en-US")
        favicon.should eq("https://example.com/favicon.ico")
        icon.should eq("https://example.com/icon.png")
      end

      it "extracts feed-level authors" do
        json = <<-JSON
          {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Test",
            "authors": [
              {"name": "Feed Author", "url": "https://example.com/author", "avatar": "https://example.com/avatar.jpg"}
            ],
            "items": []
          }
          JSON

        parsed = JSON.parse(json)
        authors = parsed["authors"]?.try(&.as_a)
        author_name = authors.try(&.first?).try(&.["name"]?.try(&.as_s))
        author_url = authors.try(&.first?).try(&.["url"]?.try(&.as_s))
        author_avatar = authors.try(&.first?).try(&.["avatar"]?.try(&.as_s))

        author_name.should eq("Feed Author")
        author_url.should eq("https://example.com/author")
        author_avatar.should eq("https://example.com/avatar.jpg")
      end

      it "requires id field and returns nil for items without id" do
        json = <<-JSON
          {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Test",
            "items": [
              {"id": "1", "content_text": "Has ID"},
              {"content_text": "No ID"}
            ]
          }
          JSON

        parsed = JSON.parse(json)
        items = parsed["items"]?.try(&.as_a) || [] of JSON::Any

        first_id = items[0]["id"]?.try(&.to_s)
        second_id = items[1]["id"]?.try(&.to_s)

        first_id.should eq("1")
        second_id.should be_nil
      end

      it "uses date_modified when date_published is missing" do
        json = <<-JSON
          {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Test",
            "items": [{
              "id": "1",
              "content_text": "Test",
              "date_modified": "2024-01-17T14:00:00Z"
            }]
          }
          JSON

        parsed = JSON.parse(json)
        item = parsed["items"][0]
        published = item["date_published"]?.try(&.as_s)
        modified = item["date_modified"]?.try(&.as_s)
        date_to_parse = published || modified

        date_to_parse.should eq("2024-01-17T14:00:00Z")
      end

      it "handles feed without authors gracefully" do
        json = <<-JSON
          {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Test",
            "items": [{"id": "1", "content_text": "Test"}]
          }
          JSON

        parsed = JSON.parse(json)
        authors = parsed["authors"]?.try(&.as_a) || parsed["author"]?.try(&.as_a)

        authors.should be_nil
      end
    end

    describe "Entry and Result with JSON Feed data" do
      it "creates entry from JSON Feed item" do
        attachment = Fetcher::Attachment.new(
          url: "https://example.com/file.mp3",
          mime_type: "audio/mpeg",
          size_in_bytes: 12345_i64
        )
        entry = Fetcher::Entry.create(
          title: "Test Post",
          url: "https://example.com/post",
          source_type: Fetcher::SourceType::JSONFeed,
          content: "<p>HTML content</p>",
          author: "John Doe",
          author_url: "https://example.com/john",
          categories: ["Tech", "News"],
          attachments: [attachment]
        )

        entry.title.should eq("Test Post")
        entry.source_type.should eq(Fetcher::SourceType::JSONFeed)
        entry.content.should eq("<p>HTML content</p>")
        entry.author.should eq("John Doe")
        entry.author_url.should eq("https://example.com/john")
        entry.categories.size.should eq(2)
        entry.attachments.size.should eq(1)
      end

      it "creates result with JSON Feed metadata" do
        author = Fetcher::Author.new(
          name: "Feed Author",
          url: "https://example.com/author",
          avatar: "https://example.com/avatar.jpg"
        )
        result = Fetcher::Result.success(
          entries: [] of Fetcher::Entry,
          feed_title: "JSON Feed Title",
          feed_description: "JSON Feed Description",
          feed_language: "en",
          feed_authors: [author],
          favicon: "https://example.com/favicon.ico"
        )

        result.feed_title.should eq("JSON Feed Title")
        result.feed_description.should eq("JSON Feed Description")
        result.feed_language.should eq("en")
        result.feed_authors.size.should eq(1)
        result.feed_authors[0].name.should eq("Feed Author")
        result.favicon.should eq("https://example.com/favicon.ico")
      end
    end
  end
end
