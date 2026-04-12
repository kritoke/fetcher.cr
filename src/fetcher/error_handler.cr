module Fetcher
  module ErrorHandler
    def self.handle_response(response : ::HTTP::Client::Response, url : String, & : -> Result) : Result
      case response.status_code
      when 304
        Result.success(entries: [] of Entry, etag: response.headers["ETag"]?, last_modified: response.headers["Last-Modified"]?)
      when 200..299
        yield
      when 500..599
        error = Error.server_error(response.status_code, "Server error: #{response.status_code}", url)
        Result.error(error)
      else
        error = Error.http(response.status_code, "HTTP #{response.status_code}", url)
        Result.error(error)
      end
    end

    def self.handle_network_error(ex : Exception, url : String) : Result
      case ex
      when IO::TimeoutError
        error = Error.timeout("Timeout: #{ex.message}", url)
        Result.error(error)
      when DNSError
        error = Error.dns("DNS error: #{ex.message}", url)
        Result.error(error)
      when MissingLocationHeaderError
        error = Error.missing_location_header("Missing Location header: #{ex.message}", url)
        Result.error(error)
      when JSON::ParseException
        error = Error.invalid_format("JSON parsing error: #{ex.message}", url)
        Result.error(error)
      when XML::Error
        error = Error.invalid_format("XML parsing error: #{ex.message}", url)
        Result.error(error)
      when FetchError
        Result.error(Error.new(kind: ErrorKind::Unknown, message: ex.message || "Fetch error", url: url))
      else
        if Fetcher.transient_error?(ex)
          error = Error.unknown(ex.message || "Unknown error", url)
          Result.error(error)
        else
          error = Error.unknown("#{ex.class}: #{ex.message}", url)
          Result.error(error)
        end
      end
    end

    def self.log_error(url : String, ex : Exception, config : RequestConfig = RequestConfig.new)
      logger = ::Log.for("fetcher")
      case config.error_detail_level
      when .minimal?
        logger.debug { "Error fetching #{url}" }
      when .normal?
        logger.debug { "Error fetching #{url}: #{ex.class}" }
      when .debug?
        logger.debug { "Error for #{url}: #{ex.class} - #{ex.message}" }
      end
    end
  end
end
