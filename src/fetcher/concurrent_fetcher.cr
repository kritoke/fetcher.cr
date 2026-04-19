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
      max_concurrent.times { semaphore.send(nil) }
      results = Channel(Tuple(Int32, Result)).new
      result_array = Array(Result?).new(urls.size, nil)

      urls.each_with_index do |url, index|
        spawn do
          begin
            semaphore.receive
            result = Fetcher.pull(url, headers, limit, config)
            results.send({index, result})
          rescue ex
            results.send({index, Fetcher.error_result(ErrorKind::Unknown, "Concurrent fetch error for #{url}: #{ex.class}: #{ex.message}")})
          ensure
            semaphore.send(nil)
          end
        end
      end

      urls.size.times do
        index, result = results.receive
        result_array[index] = result
      end
      result_array.compact
    end
  end
end
