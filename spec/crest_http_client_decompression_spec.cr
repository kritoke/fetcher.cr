require "spec"
require "compress/gzip"
require "../src/fetcher"

describe Fetcher::CrestHttpClient do
  describe ".ensure_decompressed" do
    it "returns plain text body unchanged" do
      body = "<?xml version=\"1.0\"?><rss></rss>"
      Fetcher::CrestHttpClient.ensure_decompressed(body).should eq body
    end

    it "returns empty string unchanged" do
      Fetcher::CrestHttpClient.ensure_decompressed("").should eq ""
    end

    it "returns short non-gzip body unchanged" do
      Fetcher::CrestHttpClient.ensure_decompressed("AB").should eq "AB"
    end

    it "decompresses gzip-compressed body" do
      original = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><rss><channel><title>Test</title></channel></rss>"

      # Compress with gzip
      io = IO::Memory.new
      Compress::Gzip::Writer.open(io) do |gzip|
        gzip.print(original)
      end
      compressed = io.to_s

      # Verify it starts with gzip magic bytes
      bytes = compressed.to_slice
      bytes[0].should eq 0x1f_u8
      bytes[1].should eq 0x8b_u8

      # Ensure_decompressed should decompress it
      result = Fetcher::CrestHttpClient.ensure_decompressed(compressed)
      result.should eq original
    end

    it "decompresses large gzip body" do
      # Simulate a real RSS feed with many items
      items = (1..100).map { |i| "<item><title>Item #{i}</title><link>https://example.com/#{i}</link></item>" }.join
      original = "<?xml version=\"1.0\"?><rss><channel>#{items}</channel></rss>"

      io = IO::Memory.new
      Compress::Gzip::Writer.open(io) do |gzip|
        gzip.print(original)
      end
      compressed = io.to_s

      # Compressed should be smaller
      compressed.bytesize.should be < original.bytesize

      result = Fetcher::CrestHttpClient.ensure_decompressed(compressed)
      result.should eq original
    end

    it "returns original body if gzip decompression fails" do
      # Gzip magic bytes but invalid content
      bad_gzip = Bytes[0x1f, 0x8b, 0x00, 0x00, 0x00]
      body = String.new(bad_gzip)

      result = Fetcher::CrestHttpClient.ensure_decompressed(body)
      result.should eq body
    end

    it "does not mistake binary data starting with 0x1f 0x8b for gzip if decompression fails" do
      # Coincidental magic bytes but not valid gzip
      fake = "\x1f\x8b not actually gzip content"
      result = Fetcher::CrestHttpClient.ensure_decompressed(fake)
      result.should eq fake
    end
  end
end
