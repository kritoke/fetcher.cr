module Fetcher
  module ErrorHandler
    def self.handle_response(response : ::HTTP::Client::Response, url : String, &block : -> Result) : Result
      case response.status_code
      when 304
        ResultBuilder.success(entries: [] of Entry, etag: response.headers["ETag"]?, last_modified: response.headers["Last-Modified"]?)
      when 200..299
        yield
      when 500..599
        error = Error.server_error(response.status_code, "Server error: #{response.status_code}", url)
        raise HTTPServerError.new(error.message, response.status_code, error)
      else
        error = Error.http(response.status_code, "HTTP #{response.status_code}", url)
        if (400..499).includes?(response.status_code)
          # Client errors are not retriable
          Fetcher.error_result(error)
        else
          # Other errors might be retriable
          raise HTTPError.new(error.message, response.status_code, error)
        end
      end
    end

    def self.handle_network_error(ex : Exception, url : String) : Result
      case ex
      when IO::TimeoutError
        error = Error.timeout("Timeout: #{ex.message}", url)
        raise TimeoutError.new(error.message, error)
      when CrestHttpClient::DNSError
        error = Error.dns("DNS error: #{ex.message}", url)
        raise DNSError.new(error.message, error)
      when JSON::ParseException
        error = Error.invalid_format("JSON parsing error: #{ex.message}", url)
        raise InvalidFormatError.new(error.message, error)
      when XML::Error
        error = Error.invalid_format("XML parsing error: #{ex.message}", url)
        raise InvalidFormatError.new(error.message, error)
      when FetchError
        # Re-raise typed exceptions
        raise ex
      else
        if Fetcher.transient_error?(ex)
          error = Error.unknown(ex.message || "Unknown error", url)
          raise UnknownError.new(error.message, error)
        end
        error = Error.unknown("#{ex.class}: #{ex.message}", url)
        Fetcher.error_result(error)
      end
    end
  end
end