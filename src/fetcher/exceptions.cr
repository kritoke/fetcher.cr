module Fetcher
  # Base exception for all fetcher errors
  class FetchError < Exception
    getter original_error : Error?

    def initialize(message : String, @original_error : Error? = nil)
      super(message)
    end

    def self.from_error(error : Error) : FetchError
      case error.kind
      when .dns_error?
        DNSError.new(error.message, error)
      when .timeout?
        TimeoutError.new(error.message, error)
      when .invalid_url?
        InvalidURLError.new(error.message, error)
      when .invalid_format?
        InvalidFormatError.new(error.message, error)
      when .http_error?, .server_error?
        create_http_error(error)
      when .rate_limited?
        RateLimitError.new(error.message, error)
      when .unknown?
        UnknownError.new(error.message, error)
      else
        UnknownError.new(error.message, error)
      end
    end

    private def self.create_http_error(error : Error) : FetchError
      if error.status_code
        status_code = error.status_code.as(Int32)
        if (400..499).includes?(status_code)
          HTTPClientError.new(error.message, status_code, error)
        elsif (500..599).includes?(status_code)
          HTTPServerError.new(error.message, status_code, error)
        else
          HTTPError.new(error.message, status_code, error)
        end
      else
        HTTPError.new(error.message, nil, error)
      end
    end
  end

  # Network-related errors
  class DNSError < FetchError
    def initialize(message : String, original_error : Error? = nil)
      super(message, original_error)
    end
  end

  class TimeoutError < FetchError
    def initialize(message : String, original_error : Error? = nil)
      super(message, original_error)
    end
  end

  # Validation errors
  class InvalidURLError < FetchError
    def initialize(message : String, original_error : Error? = nil)
      super(message, original_error)
    end
  end

  class InvalidFormatError < FetchError
    def initialize(message : String, original_error : Error? = nil)
      super(message, original_error)
    end
  end

  # HTTP errors
  class HTTPError < FetchError
    getter status_code : Int32?

    def initialize(message : String, @status_code : Int32? = nil, original_error : Error? = nil)
      super(message, original_error)
    end
  end

  class HTTPClientError < HTTPError
    def initialize(message : String, @status_code : Int32, original_error : Error? = nil)
      super(message, @status_code, original_error)
    end
  end

  class HTTPServerError < HTTPError
    def initialize(message : String, @status_code : Int32, original_error : Error? = nil)
      super(message, @status_code, original_error)
    end
  end

  # Rate limiting
  class RateLimitError < FetchError
    def initialize(message : String, original_error : Error? = nil)
      super(message, original_error)
    end
  end

  # Unknown errors
  class UnknownError < FetchError
    def initialize(message : String, original_error : Error? = nil)
      super(message, original_error)
    end
  end
end
