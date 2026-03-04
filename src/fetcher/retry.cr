require "./fetch_error"

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
            return error_result(Error.timeout("Failed after retries: #{ex.message}"))
          end
          sleep(config.delay_for_attempt(attempt))
        else
          return error_result(Error.unknown("#{ex.class}: #{ex.message}"))
        end
      end
    end
  end

  def self.error_result(err : Error) : Result
    Result.error(err)
  end

  def self.error_result(kind : ErrorKind, message : String, status_code : Int32? = nil) : Result
    Result.error(Error.new(kind: kind, message: message, status_code: status_code))
  end

  def self.transient_error?(ex : Exception) : Bool
    msg = ex.message.to_s.downcase
    msg.includes?("timeout") || msg.includes?("connection") || msg.includes?("dns")
  end
end
