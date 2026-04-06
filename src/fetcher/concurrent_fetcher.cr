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
      results = Channel(Tuple(Int32, Result)).new
      result_array = [] of Result

      urls.each_with_index do |url, index|
        semaphore.send(nil)
        spawn do
          begin
            results.send({index, Fetcher.pull(url, headers, limit, config)})
          rescue ex
            results.send({index, Fetcher.error_result(ErrorKind::Unknown, "Concurrent fetch error for #{url}: #{ex.class}: #{ex.message}")})
          ensure
            semaphore.receive
          end
        end
      end

      urls.size.times { result_array << results.receive[1] }
      result_array
    end
  end
end
