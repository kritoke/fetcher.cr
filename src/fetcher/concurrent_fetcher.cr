require "./request_config"
require "./result"
require "./adaptive_concurrency_controller"
require "../fetcher"
require "./exceptions"

module Fetcher
  # Concurrent feed fetching with adaptive concurrency control
  class ConcurrentFetcher
    def self.pull_multiple(urls : Array(String), headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Array(Result)
      # Create adaptive concurrency controller
      concurrency_controller = AdaptiveConcurrencyController.new(config)

      # Use channels for concurrent execution
      results_channel = Channel(Result).new
      error_channel = Channel(Exception).new

      # Spawn fibers for each URL
      urls.each do |url|
        spawn do
          begin
            concurrency_controller.acquire
            result = Fetcher.pull(url, headers, limit, config)
            results_channel.send(result)
          rescue ex
            error_channel.send(ex)
          ensure
            concurrency_controller.release
          end
        end
      end

      # Collect results
      results = [] of Result
      urls.size.times do
        select
        when result = results_channel.receive
          results << result
        when error = error_channel.receive
          # Handle errors appropriately
          results << Fetcher.error_result(ErrorKind::Unknown, "Concurrent fetch error: #{error.message}")
        end
      end

      results
    end
  end
end
