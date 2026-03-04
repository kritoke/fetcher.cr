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
    status_code : Int32? = nil,
    url : String? = nil,
    driver : String? = nil do
    def self.dns(message : String, url : String? = nil) : Error
      new(kind: ErrorKind::DNSError, message: message, url: url)
    end

    def self.timeout(message : String, url : String? = nil) : Error
      new(kind: ErrorKind::Timeout, message: message, url: url)
    end

    def self.invalid_url(message : String = "Invalid URL", url : String? = nil) : Error
      new(kind: ErrorKind::InvalidURL, message: message, url: url)
    end

    def self.invalid_format(message : String, url : String? = nil) : Error
      new(kind: ErrorKind::InvalidFormat, message: message, url: url)
    end

    def self.http(status_code : Int32, message : String? = nil, url : String? = nil) : Error
      new(
        kind: ErrorKind::HTTPError,
        message: message || "HTTP #{status_code}",
        status_code: status_code,
        url: url
      )
    end

    def self.rate_limited(message : String = "Rate limited", url : String? = nil) : Error
      new(kind: ErrorKind::RateLimited, message: message, url: url)
    end

    def self.server_error(status_code : Int32, message : String? = nil, url : String? = nil) : Error
      new(
        kind: ErrorKind::ServerError,
        message: message || "Server error #{status_code}",
        status_code: status_code,
        url: url
      )
    end

    def self.unknown(message : String, url : String? = nil) : Error
      new(kind: ErrorKind::Unknown, message: message, url: url)
    end

    def to_s : String
      message
    end
  end
end
