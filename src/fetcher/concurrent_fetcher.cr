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

      # Collect results with a wall-clock deadline. If no result arrives
      # within `timeout` we return whatever we have so the call can't hang.
      deadline = Time.instant + timeout
      received = 0

      loop do
        break if received >= urls.size

        # How much time remains before the deadline?
        remaining = deadline - Time.instant
        break if remaining <= Time::Span.zero

        # Wait for either a result or the remaining budget.
        select
        when result = results.receive?
          if result
            index, outcome = result
            result_array[index] = store_outcome(outcome, urls[index])
            received += 1
          else
            # Channel closed - no more results
            break
          end
        when timeout remaining
          ::Log.for("fetcher").warn { "Concurrent fetch timed out after #{timeout}, returning #{received}/#{urls.size} results" }
          break
        end
      end

      result_array.compact
    end

    # Convert a single worker's outcome into a Result for the result array.
    # Successful Results pass through; exceptions are wrapped so the caller
    # sees a uniform Result type per slot.
    private def self.store_outcome(outcome : Result | Exception, url : String) : Result
      case outcome
      when Result then outcome
      when Exception
        Fetcher.error_result(ErrorKind::Unknown, "Concurrent fetch error for #{url}: #{outcome.class} - #{outcome.message}")
      else
        # Unreachable: outcome is statically `Result | Exception`, both arms handled.
        Fetcher.error_result(ErrorKind::Unknown, "Concurrent fetch unknown outcome for #{url}")
      end
    end
  end
end
