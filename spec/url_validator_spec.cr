require "spec"
require "../src/fetcher"

describe Fetcher::URLValidator do
  it "recognizes bracketed IPv6 as IP" do
    Fetcher::URLValidator.looks_like_ip?("[::1]").should be_true
  end

  it "recognizes IPv4 dotted notation" do
    Fetcher::URLValidator.looks_like_ip?("192.168.1.1").should be_true
  end

  it "recognizes mapped IPv4 (::ffff:192.168.1.1)" do
    Fetcher::URLValidator.looks_like_ip?("::ffff:192.168.1.1").should be_true
  end

  it "does not treat normal hostnames starting with digits as IPs unless valid" do
    Fetcher::URLValidator.looks_like_ip?("123example.com").should be_false
  end
end
