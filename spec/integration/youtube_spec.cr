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

    it "detects YouTube @handle URLs" do
      Fetcher.detect_driver("https://www.youtube.com/@somehandle").should eq(Fetcher::DriverType::YouTube)
    end

    it "detects YouTube /c/ custom URLs" do
      Fetcher.detect_driver("https://www.youtube.com/c/customname").should eq(Fetcher::DriverType::YouTube)
    end

    it "detects YouTube /user/ URLs" do
      Fetcher.detect_driver("https://www.youtube.com/user/username").should eq(Fetcher::DriverType::YouTube)
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

    it "parses YouTube feed with yt:channelId namespace" do
      channel_id = "UCyyyyyyyyyyyyyyyyyy"
      youtube_rss = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:yt="http://www.youtube.com/xml/schemas/2015">
          <entry>
            <title>Test Video</title>
            <link href="https://www.youtube.com/watch?v=xyz789"/>
            <published>2024-01-20T12:00:00+00:00</published>
            <yt:channelId>UCyyyyyyyyyyyyyyyyyy</yt:channelId>
          </entry>
        </feed>
        XML

      result = Fetcher::YouTube.parse_youtube_feed(youtube_rss, channel_id, 100)
      result.success?.should be_true
      result.entries.size.should eq(1)
      result.entries.first.source_type.should eq(Fetcher::SourceType::YouTube)
    end
  end
end
