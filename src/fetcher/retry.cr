require "./fetch_error"
require "./exceptions"

module Fetcher
  RETRY_JITTER_MIN = 0.9
  RETRY_JITTER_MAX = 1.1

  class RetriableError < Exception
    def initialize(message : String)
      super(message)
    end
  end

  def self.with_retry(
    config : RequestConfig,
    is_retriable : Exception -> Bool = ->(ex : Exception) { ex.is_a?(RetriableError) || transient_error?(ex) },
    &operation : -> Result
  ) : Result
    attempt = 0
    max_retries = config.retry.max_retries
    max_retries = 0 if max_retries < 0
    loop do
      begin
        return operation.call
      rescue ex
        if is_retriable.call(ex)
          attempt += 1
          if attempt > max_retries
            return error_result(Error.unknown("Max retries (#{max_retries}) exceeded: #{ex.class}: #{ex.message}"))
          end
          delay = config.delay_for_attempt(attempt)
          jitter_factor = RETRY_JITTER_MIN + (Random.rand * (RETRY_JITTER_MAX - RETRY_JITTER_MIN))
          actual_delay = delay * jitter_factor
          sleep(actual_delay)
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
    if ex.is_a?(Reddit::RedditFetchError)
      ex.original_cause.try { |cause| return transient_error?(cause) }
    end

    case ex
    when DNSError, TimeoutError, HTTPClientError, IO::TimeoutError
      return true
    when HTTPError
      return true unless sc = ex.status_code
      (500..599).includes?(sc)
    end

    msg = ex.message.to_s.downcase
    msg.includes?("timeout") || msg.includes?("connection") || msg.includes?("dns")
  end
end
