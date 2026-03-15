require "./exceptions"
require "./result"

module Fetcher
  # Comprehensive error handling for streaming parsers
  module StreamingErrorHandling
    # Handle streaming parser errors with appropriate fallback behavior
    def self.handle_streaming_error(
      ex : Exception,
      config : RequestConfig,
      feed_type : Symbol,
      url : String? = nil
    ) : Exception
      case ex
      when XML::Error, JSON::ParseException
        # Parsing errors - these are expected and should fallback to DOM
        log_fallback(config, "parsing", feed_type, url, ex)
        ex
      when IO::Error
        # I/O errors - may be transient or permanent
        if is_transient_io_error?(ex)
          log_fallback(config, "transient I/O", feed_type, url, ex)
          ex
        else
          # Permanent I/O error
          log_error(config, "permanent I/O", feed_type, url, ex)
          create_fetch_error(ex, ErrorKind::Unknown, url)
        end
      when MemoryLimitExceeded
        # Memory limit exceeded - don't fallback to avoid OOM
        log_error(config, "memory limit", feed_type, url, ex)
        create_fetch_error(ex, ErrorKind::InvalidFormat, url, "Feed too large for streaming parser")
      else
        # Unknown errors - treat as transient and fallback
        log_fallback(config, "unknown", feed_type, url, ex)
        ex
      end
    end

    # Check if an I/O error is likely transient
    private def self.is_transient_io_error?(ex : IO::Error) : Bool
      # Common transient errors
      message = ex.message.to_s.downcase
      message.includes?("timeout") ||
      message.includes?("connection reset") ||
      message.includes?("broken pipe") ||
      message.includes?("network") ||
      message.includes?("ssl")
    end

    # Log fallback information (only if debug enabled)
    private def self.log_fallback(config : RequestConfig, error_type : String, feed_type : Symbol, url : String?, ex : Exception)
      return unless config.debug_streaming
      
      url_str = url ? " for #{url}" : ""
      puts "Streaming parser #{error_type} error#{url_str} (#{feed_type}): #{ex.class} - #{ex.message}"
      puts "  Falling back to DOM parser..."
    end

    # Log error information (only if debug enabled)
    private def self.log_error(config : RequestConfig, error_type : String, feed_type : Symbol, url : String?, ex : Exception)
      return unless config.debug_streaming
      
      url_str = url ? " for #{url}" : ""
      puts "Streaming parser #{error_type} error#{url_str} (#{feed_type}): #{ex.class} - #{ex.message}"
      puts "  Not falling back to avoid resource issues"
    end

    # Create appropriate fetch error
    private def self.create_fetch_error(ex : Exception, kind : ErrorKind, url : String?, message : String? = nil) : FetchError
      error_message = message || "#{ex.class}: #{ex.message}"
      error = Error.new(kind: kind, message: error_message, url: url)
      FetchError.from_error(error)
    end

    # Custom exception for memory limit exceeded
    class MemoryLimitExceeded < Exception
      def initialize(message : String = "Memory limit exceeded during streaming parsing")
        super(message)
      end
    end
  end
end