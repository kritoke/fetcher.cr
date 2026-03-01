module Fetcher
  record RetryConfig,
    max_retries : Int32 = 3,
    base_delay : Time::Span = 1.second,
    max_delay : Time::Span = 30.seconds,
    exponential_base : Float64 = 2.0 do
    def delay_for_attempt(attempt : Int32) : Time::Span
      delay = base_delay * (exponential_base ** attempt)
      delay = max_delay if delay > max_delay
      delay
    end
  end

  DEFAULT_RETRY_CONFIG = RetryConfig.new

  class RetriableError < Exception
    def initialize(message : String)
      super(message)
    end
  end

  def self.with_retry(
    config : RetryConfig = DEFAULT_RETRY_CONFIG,
    is_retriable : Exception -> Bool = ->(ex : Exception) { ex.is_a?(RetriableError) },
    &operation : -> Result
  ) : Result
    attempt = 0
    loop do
      begin
        return operation.call
      rescue ex
        if is_retriable.call(ex)
          attempt += 1
          if attempt >= config.max_retries
            return error_result("Failed after retries: #{ex.message}")
          end
          sleep(config.delay_for_attempt(attempt))
        else
          return error_result("#{ex.class}: #{ex.message}")
        end
      end
    end
  end

  def self.error_result(message : String) : Result
    Result.error(message)
  end

  def self.transient_error?(ex : Exception) : Bool
    msg = ex.message.to_s.downcase
    msg.includes?("timeout") || msg.includes?("connection") || msg.includes?("dns")
  end
end
