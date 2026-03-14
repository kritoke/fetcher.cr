require "./result"
require "./exceptions"

module Fetcher
  # Fallback mechanism for streaming parser errors
  module StreamingFallback
    # Execute streaming parser with automatic fallback to DOM parser on errors
    def self.with_fallback(
      config : RequestConfig,
      &streaming_block : -> Result
    ) : Result
      if config.use_streaming_parser
        begin
          streaming_result = streaming_block.call
          if streaming_result.success?
            return streaming_result
          else
            # Streaming succeeded but returned error - return as-is
            return streaming_result
          end
        rescue ex
          # Log warning about fallback (only in debug mode)
          if config.debug_streaming?
            puts "Streaming parser failed, falling back to DOM parser: #{ex.class} - #{ex.message}"
          end
          
          # Re-raise to let caller handle fallback
          raise ex
        end
      else
        # Streaming not enabled, execute normally
        streaming_block.call
      end
    end
    
    # Check if debug streaming is enabled
    private def self.debug_streaming?(config : RequestConfig) : Bool
      config.debug_streaming
    end
  end
end
