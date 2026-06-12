require "./fetch_error"

module Fetcher
  class FetchError < Exception
    getter original_error : Error?
    getter cause : Exception?

    def initialize(message : String, @original_error : Error? = nil, @cause : Exception? = nil)
      super(message)
    end
  end

  macro define_fetch_error(name, superclass = FetchError)
    class {{ name }} < {{ superclass.id }}
      def initialize(message : String, original_error : Error? = nil, cause : Exception? = nil)
        super(message, original_error, cause)
      end
    end
  end

  define_fetch_error DNSError
  define_fetch_error TimeoutError
  define_fetch_error InvalidURLError
  define_fetch_error InvalidFormatError
  define_fetch_error SSLError

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

  define_fetch_error CircuitOpenError
  define_fetch_error RateLimitError
  define_fetch_error UnknownError
  define_fetch_error ResponseTooLargeError
  define_fetch_error MissingLocationHeaderError

  # Raised when Reddit OAuth token acquisition fails
  class RedditOAuthError < FetchError
    def initialize(message : String, original_error : Error? = nil, cause : Exception? = nil)
      super(message, original_error, cause)
    end
  end

  class MemoryLimitExceeded < FetchError
    def initialize(message : String = "Memory limit exceeded during streaming parsing")
      super(message)
    end
  end

  class QueueFullError < Exception
    def initialize(message : String = "Rate limiter waiter queue is full")
      super(message)
    end
  end
end
