require "./request_config"
require "./result"
require "../fetcher"
require "./exceptions"

module Fetcher
  class ConcurrentFetcher
    DEFAULT_MAX_CONCURRENT = 16

    def self.pull_multiple(
      urls : Array(String),
      headers : ::HTTP::Headers = ::HTTP::Headers.new,
      limit : Int32 = 100,
      max_concurrent : Int32 = DEFAULT_MAX_CONCURRENT,
      config : RequestConfig = RequestConfig.new,
    ) : Array(Result)
      semaphore = Channel(Nil).new(max_concurrent)
      results = Channel(Result).new

      urls.each do |url|
        spawn do
          semaphore.send(nil)
          begin
            results << Fetcher.pull(url, headers, limit, config)
          rescue ex
            results << Fetcher.error_result(ErrorKind::Unknown, "Concurrent fetch error: #{ex.message}")
          ensure
            semaphore.receive rescue nil
          end
        end
      end

      urls.size.times { results.receive }
    end
  end
end
