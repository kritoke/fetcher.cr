require "spec"
require "../../src/fetcher"

describe "Integration Tests - YouTube" do
  describe "URL detection" do
    it "detects YouTube channel URLs" do
      Fetcher.detect_driver("https://www.youtube.com/channel/UCxxxxxxxxxxxxxxxxxx").should eq(Fetcher::DriverType::YouTube)
    end

    it "detects YouTube channel URLs without www" do
      Fetcher.detect_driver("https://youtube.com/channel/UCxxxxxxxxxxxxxxxxxx").should eq(Fetcher::DriverType::YouTube)
    end

    it "does not detect other YouTube URLs as YouTube driver" do
      Fetcher.detect_driver("https://www.youtube.com/@handle").should_not eq(Fetcher::DriverType::YouTube)
      Fetcher.detect_driver("https://www.youtube.com/c/customname").should_not eq(Fetcher::DriverType::YouTube)
      Fetcher.detect_driver("https://www.youtube.com/user/username").should_not eq(Fetcher::DriverType::YouTube)
    end
  end

  describe "channel ID extraction" do
    it "rejects @handle URLs" do
      url = "https://www.youtube.com/@somehandle"
      result = Fetcher.pull_youtube(url)
      result.success?.should be_false
      result.error_message.should_not be_nil
      result.error_message.not_nil!.should contain("Not a valid YouTube channel URL")
    end

    it "rejects /c/ custom URLs" do
      url = "https://www.youtube.com/c/customname"
      result = Fetcher.pull_youtube(url)
      result.success?.should be_false
      result.error_message.should_not be_nil
      result.error_message.not_nil!.should contain("Not a valid YouTube channel URL")
    end

    it "rejects /user/ URLs" do
      url = "https://www.youtube.com/user/username"
      result = Fetcher.pull_youtube(url)
      result.success?.should be_false
      result.error_message.should_not be_nil
      result.error_message.not_nil!.should contain("Not a valid YouTube channel URL")
    end
  end

  describe "SourceType" do
    it "includes YouTube in SourceType enum" do
      Fetcher::SourceType::YouTube.to_s.should eq("youtube")
    end

    it "parses YouTube from string" do
      Fetcher::SourceType.from_string("youtube").should eq(Fetcher::SourceType::YouTube)
    end
  end

  describe "feed parsing" do
    it "parses YouTube RSS feed and sets correct source type" do
      channel_id = "UCxxxxxxxxxxxxxxxxxx"
      youtube_rss = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Test Video Title</title>
            <link href="https://www.youtube.com/watch?v=abc123"/>
            <published>2024-01-15T10:00:00+00:00</published>
          </entry>
        </feed>
        XML

      result = Fetcher::YouTube.parse_youtube_feed(youtube_rss, channel_id, 100)
      result.success?.should be_true
      result.entries.size.should eq(1)
      result.entries.first.title.should eq("Test Video Title")
      result.entries.first.url.should eq("https://www.youtube.com/watch?v=abc123")
      result.entries.first.source_type.should eq(Fetcher::SourceType::YouTube)
      result.site_link.should eq("https://www.youtube.com/channel/#{channel_id}")
      result.favicon.should eq("https://www.youtube.com/favicon.ico")
    end
  end
end
