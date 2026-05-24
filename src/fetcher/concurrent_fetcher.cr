require "./request_config"
require "./result"
require "../fetcher"
require "./exceptions"

module Fetcher
  class ConcurrentFetcher
    DEFAULT_MAX_CONCURRENT =   16
    DEFAULT_MAX_PENDING    = 1000
    DEFAULT_TIMEOUT       = 60.seconds

    def self.pull_multiple(
      urls : Array(String),
      headers : ::HTTP::Headers = ::HTTP::Headers.new,
      limit : Int32 = 100,
      max_concurrent : Int32 = DEFAULT_MAX_CONCURRENT,
      config : RequestConfig = RequestConfig.new,
      max_pending : Int32 = DEFAULT_MAX_PENDING,
      timeout : Time::Span = DEFAULT_TIMEOUT,
    ) : Array(Result)
      return [] of Result if urls.empty?

      semaphore = Channel(Nil).new(max_concurrent)
      max_concurrent.times { semaphore.send(nil) }
      # Use bounded channel to prevent memory blowup
      results = Channel(Tuple(Int32, Result | Exception)).new(urls.size)
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
              pending_count.sub(1)
            end
          end
        end
      end

      # Collect results with timeout to prevent hanging forever
      deadline = Time.monotonic + timeout
      received = 0
      timed_out = false

      while received < urls.size && !timed_out
        message = results.receive?
        if message.nil?
          # Channel closed or timeout
          break
        end

        index, outcome = message
        result_array[index] = case outcome
                              when Result
                                outcome
                              when Exception
                                Fetcher.error_result(ErrorKind::Unknown, "Concurrent fetch error for #{urls[index]}: #{outcome.class}: #{outcome.message}")
                              end
        received += 1

        # Check timeout
        if Time.monotonic > deadline
          ::Log.for("fetcher").warn { "Concurrent fetch timed out after #{timeout}, returning #{received}/#{urls.size} results" }
          timed_out = true
        end
      end

      result_array.compact
    end
  end
end