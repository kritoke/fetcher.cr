module Fetcher
  enum ErrorKind
    DNSError
    Timeout
    InvalidURL
    InvalidFormat
    HTTPError
    RateLimited
    ServerError
    Unknown
  end

  record Error,
    kind : ErrorKind,
    message : String,
    status_code : Int32? = nil do
    def self.dns(message : String) : Error
      new(kind: ErrorKind::DNSError, message: message)
    end

    def self.timeout(message : String) : Error
      new(kind: ErrorKind::Timeout, message: message)
    end

    def self.invalid_url(message : String = "Invalid URL") : Error
      new(kind: ErrorKind::InvalidURL, message: message)
    end

    def self.invalid_format(message : String) : Error
      new(kind: ErrorKind::InvalidFormat, message: message)
    end

    def self.http(status_code : Int32, message : String? = nil) : Error
      new(
        kind: ErrorKind::HTTPError,
        message: message || "HTTP #{status_code}",
        status_code: status_code
      )
    end

    def self.rate_limited(message : String = "Rate limited") : Error
      new(kind: ErrorKind::RateLimited, message: message)
    end

    def self.server_error(status_code : Int32, message : String? = nil) : Error
      new(
        kind: ErrorKind::ServerError,
        message: message || "Server error #{status_code}",
        status_code: status_code
      )
    end

    def self.unknown(message : String) : Error
      new(kind: ErrorKind::Unknown, message: message)
    end

    def to_s : String
      message
    end
  end
end
