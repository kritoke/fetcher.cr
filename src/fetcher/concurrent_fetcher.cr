require "./request_config"
require "./result"
require "../fetcher"
require "./exceptions"

module Fetcher
  class ConcurrentFetcher
    DEFAULT_MAX_CONCURRENT =   16
    DEFAULT_MAX_PENDING    = 1000
    DEFAULT_TIMEOUT        = 60.seconds

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
        spawn do
          # Use CAS loop to atomically check-and-increment pending_count
          # This prevents the TOCTOU race condition
          loop do
            current = pending_count.get
            if current >= max_pending
              begin
                results.send({index, QueueFullError.new("Too many pending requests")})
              rescue Channel::ClosedError
                # Results channel closed - skip silently
              end
              break
            elsif pending_count.compare_and_set(current, current + 1)
              break # CAS succeeded, we acquired the slot - proceed to fetch
            end
            # CAS failed (someone else incremented), retry
          end

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

      # Collect results with timeout to prevent hanging everlasting
      deadline = Time.instant + timeout
      received = 0
      timeout_channel = Channel(Bool).new

      # Spawn timeout notifier
      spawn do
        sleep timeout
        timeout_channel.send(true)
      end

      loop do
        break if received >= urls.size

        # Use select to check for results or timeout
        selected = select
        when result = results.receive?
          if result
            index, outcome = result
            result_array[index] = case outcome
                                  when Result
                                    outcome
                                  when Exception
                                    Fetcher.error_result(ErrorKind::Unknown, "Concurrent fetch error for #{urls[index]}: #{outcome.class}: #{outcome.message}")
                                  end
            received += 1
          else
            # Channel closed - no more results
            break
          end
        when timeout_channel.receive
          # Timeout fired
          ::Log.for("fetcher").warn { "Concurrent fetch timed out after #{timeout}, returning #{received}/#{urls.size} results" }
          break
        end
      end

      result_array.compact
    end
  end
end
