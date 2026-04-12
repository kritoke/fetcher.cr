require "spec"
require "../../src/fetcher"

describe "Security: URL Sanitization" do
  describe "URLValidator.safe_scheme?" do
    it "allows http scheme" do
      Fetcher::URLValidator.safe_scheme?("http://example.com").should be_true
    end

    it "allows https scheme" do
      Fetcher::URLValidator.safe_scheme?("https://example.com").should be_true
    end

    it "allows schemeless relative URLs" do
      Fetcher::URLValidator.safe_scheme?("/comments/123").should be_true
      Fetcher::URLValidator.safe_scheme?("comments/123").should be_true
    end

    it "allows empty and nil URLs" do
      Fetcher::URLValidator.safe_scheme?("").should be_true
      Fetcher::URLValidator.safe_scheme?(nil).should be_true
    end

    it "blocks javascript: scheme" do
      Fetcher::URLValidator.safe_scheme?("javascript:alert(1)").should be_false
    end

    it "blocks data: scheme" do
      Fetcher::URLValidator.safe_scheme?("data:text/html,<script>alert(1)</script>").should be_false
    end

    it "blocks vbscript: scheme" do
      Fetcher::URLValidator.safe_scheme?("vbscript:MsgBox(1)").should be_false
    end

    it "blocks file: scheme" do
      Fetcher::URLValidator.safe_scheme?("file:///etc/passwd").should be_false
    end

    it "blocks ftp: scheme" do
      Fetcher::URLValidator.safe_scheme?("ftp://example.com/file").should be_false
    end
  end

  describe "EntryFactory sanitization" do
    it "sanitizes comment_url with javascript: scheme" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        comment_url: "javascript:alert(1)"
      )
      entry.comment_url.should be_nil
    end

    it "sanitizes commentary_url with data: scheme" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        commentary_url: "data:text/html,<script>alert(1)</script>"
      )
      entry.commentary_url.should be_nil
    end

    it "sanitizes author_url with vbscript: scheme" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        author_url: "vbscript:MsgBox(1)"
      )
      entry.author_url.should be_nil
    end

    it "preserves valid http comment_url" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        comment_url: "https://example.com/comments/1"
      )
      entry.comment_url.should eq("https://example.com/comments/1")
    end

    it "preserves relative comment_url" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        comment_url: "/comments/1"
      )
      entry.comment_url.should eq("/comments/1")
    end

    it "sanitizes attachment URL with javascript: scheme" do
      attachment = Fetcher::Attachment.new(url: "javascript:alert(1)", mime_type: "image/png")
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        attachments: [attachment]
      )
      entry.attachments.size.should eq(1)
      entry.attachments[0].url.should eq("#")
    end

    it "preserves valid http attachment URL" do
      attachment = Fetcher::Attachment.new(url: "https://example.com/image.png", mime_type: "image/png")
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        attachments: [attachment]
      )
      entry.attachments[0].url.should eq("https://example.com/image.png")
    end

    it "sanitizes content_html" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        content_html: "<p>Hello</p><script>alert('xss')</script>"
      )
      result = entry.content_html
      result.should_not be_nil
      result.as(String).should_not contain("<script>")
    end

    it "allows safe HTML in content_html" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        content_html: "<p>Hello <b>world</b></p>"
      )
      result = entry.content_html
      result.should_not be_nil
      result.as(String).should contain("Hello")
    end

    it "returns nil for empty content_html" do
      entry = Fetcher::Entry.create(
        title: "Test",
        url: "https://example.com",
        source_type: Fetcher::SourceType::RSS,
        content_html: ""
      )
      entry.content_html.should be_nil
    end
  end
end
