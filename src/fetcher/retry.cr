require "./fetch_error"
require "./exceptions"

module Fetcher
  # Retry configuration is now part of RequestConfig
  DEFAULT_RETRY_CONFIG_MAX_RETRIES      = 3
  DEFAULT_RETRY_CONFIG_BASE_DELAY       = 1.second
  DEFAULT_RETRY_CONFIG_MAX_DELAY        = 30.seconds
  DEFAULT_RETRY_CONFIG_EXPONENTIAL_BASE = 2.0

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
    loop do
      begin
        return operation.call
      rescue ex
        if is_retriable.call(ex)
          attempt += 1
          if attempt >= config.max_retries
            return error_result(Error.timeout("Failed after #{config.max_retries} retries: #{ex.message}"))
          end
          delay = config.base_delay * (config.exponential_base ** attempt)
          delay = config.max_delay if delay > config.max_delay
          sleep(delay)
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
    # Check for typed exceptions first
    case ex
    when DNSError, TimeoutError, HTTPClientError
      return true
    when HTTPError
      # Client errors (4xx) are not transient, server errors (5xx) are
      if ex.status_code.nil?
        return true
      else
        status_code = ex.status_code.as(Int32)
        return (500..599).includes?(status_code)
      end
    end

    # Fallback to string matching for legacy exceptions
    msg = ex.message.to_s.downcase
    msg.includes?("timeout") || msg.includes?("connection") || msg.includes?("dns")
  end
end
