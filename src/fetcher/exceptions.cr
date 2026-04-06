require "./fetch_error"

module Fetcher
  # Base exception for all fetcher errors
  class FetchError < Exception
    getter original_error : Error?
    getter cause : Exception?

    def initialize(message : String, @original_error : Error? = nil, @cause : Exception? = nil)
      super(message)
    end
  end

  # Network-related errors
  class DNSError < FetchError
    def initialize(message : String, original_error : Error? = nil, cause : Exception? = nil)
      super(message, original_error, cause)
    end
  end

  class TimeoutError < FetchError
    def initialize(message : String, original_error : Error? = nil, cause : Exception? = nil)
      super(message, original_error, cause)
    end
  end

  # Validation errors
  class InvalidURLError < FetchError
    def initialize(message : String, original_error : Error? = nil, cause : Exception? = nil)
      super(message, original_error, cause)
    end
  end

  class InvalidFormatError < FetchError
    def initialize(message : String, original_error : Error? = nil, cause : Exception? = nil)
      super(message, original_error, cause)
    end
  end

  # HTTP errors
  class HTTPError < FetchError
    getter status_code : Int32?

    def initialize(message : String, @status_code : Int32? = nil, original_error : Error? = nil, cause : Exception? = nil)
      super(message, original_error, cause)
    end
  end

  class HTTPClientError < HTTPError
    def initialize(message : String, @status_code : Int32, original_error : Error? = nil, cause : Exception? = nil)
      super(message, @status_code, original_error, cause)
    end
  end

  class HTTPServerError < HTTPError
    def initialize(message : String, @status_code : Int32, original_error : Error? = nil, cause : Exception? = nil)
      super(message, @status_code, original_error, cause)
    end
  end

  # Circuit breaker
  class CircuitOpenError < FetchError
    getter domain : String

    def initialize(@domain : String, original_error : Error? = nil, cause : Exception? = nil)
      super("Circuit breaker open for domain: #{@domain}", original_error, cause)
    end
  end

  # Rate limiting
  class RateLimitError < FetchError
    def initialize(message : String, original_error : Error? = nil, cause : Exception? = nil)
      super(message, original_error, cause)
    end
  end

  # Unknown errors
  class UnknownError < FetchError
    def initialize(message : String, original_error : Error? = nil, cause : Exception? = nil)
      super(message, original_error, cause)
    end
  end

  # Size limit errors
  class ResponseTooLargeError < FetchError
    def initialize(message : String, original_error : Error? = nil, cause : Exception? = nil)
      super(message, original_error, cause)
    end
  end

  # HTTP protocol errors
  class MissingLocationHeaderError < FetchError
    def initialize(message : String, original_error : Error? = nil, cause : Exception? = nil)
      super(message, original_error, cause)
    end
  end

  # Streaming errors
  class MemoryLimitExceeded < FetchError
    def initialize(message : String = "Memory limit exceeded during streaming parsing")
      super(message)
    end
  end
end
