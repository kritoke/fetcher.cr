require "./request_config"
require "./result"
require "../fetcher"
require "./exceptions"

module Fetcher
  class ConcurrentFetcher
    DEFAULT_MAX_CONCURRENT =   16
    DEFAULT_MAX_PENDING    = 1000

    def self.pull_multiple(
      urls : Array(String),
      headers : ::HTTP::Headers = ::HTTP::Headers.new,
      limit : Int32 = 100,
      max_concurrent : Int32 = DEFAULT_MAX_CONCURRENT,
      config : RequestConfig = RequestConfig.new,
      max_pending : Int32 = DEFAULT_MAX_PENDING,
    ) : Array(Result)
      return [] of Result if urls.empty?

      semaphore = Channel(Nil).new(max_concurrent)
      max_concurrent.times { semaphore.send(nil) }
      results = Channel(Tuple(Int32, Result | Exception)).new
      result_array = Array(Result?).new(urls.size, nil)
      pending_count = Atomic(Int32).new(0)

      urls.each_with_index do |url, index|
        if pending_count.get >= max_pending
          results.send({index, QueueFullError.new("Too many pending requests")})
        else
          pending_count.add(1)
          spawn do
            begin
              semaphore.receive
              result = Fetcher.pull(url, headers, limit, config)
              results.send({index, result})
            rescue ex
              results.send({index, ex})
            ensure
              semaphore.send(nil)
              current = pending_count.get
              pending_count.sub(1) if current > 0
            end
          end
        end
      end

      urls.size.times do
        index, result = results.receive
        result_array[index] = case result
                              when Result
                                result
                              when Exception
                                Fetcher.error_result(ErrorKind::Unknown, "Concurrent fetch error for #{urls[index]}: #{result.class}: #{result.message}")
                              end
      end
      result_array.compact
    end
  end
end
