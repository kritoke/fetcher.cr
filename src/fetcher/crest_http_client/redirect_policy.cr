module Fetcher
  class CrestHttpClient
    # Redirect policy extracted from CrestHttpClient. Pure functions of
    # (config, validator, source, target, status_code) -- no HTTP execution,
    # no DNS, no state. Unit-testable in isolation; co-locating the policy
    # rules here makes audit and policy-change review a single-file exercise.
    class RedirectPolicy
      REDIRECT_STATUS_CODES = {301, 302, 303, 307, 308}

      def initialize(@config : RequestConfig, @validator : URLValidator::Service)
      end

      def follow?(response : Crest::Response) : Bool
        REDIRECT_STATUS_CODES.includes?(response.status_code)
      end

      def extract_url(response : Crest::Response) : String
        extract_url_from_headers(response.headers)
      end

      def extract_url_from_headers(headers : Hash(String, String | Array(String))) : String
        redirect_url = headers["location"]? || headers["Location"]?
        raise MissingLocationHeaderError.new("Redirect response without Location header") if redirect_url.nil?

        # When headers contain multiple Location values, prefer the first one.
        value = if redirect_url.is_a?(Array)
                  redirect_url.first.to_s
                else
                  redirect_url.to_s
                end

        value = value.strip
        raise MissingLocationHeaderError.new("Redirect response without Location header") if value.empty?
        value
      end

      def validate_target(url : String) : Nil
        return if @validator.valid?(url) && @validator.resolve_and_validate(url)
        # NOTE(catseye): We include the target URL in the DNSError message for diagnostics/logging.
        # This is intentional and does not execute or evaluate the URL. Treat as informational.
        raise DNSError.new("Redirect to blocked URL: #{url}")
      end

      def validate_domain(original_url : String, source_domain : String, target_url : String, target_domain : String, status_code : Int32 = 302) : Nil
        return if allow?(source_domain, target_domain, status_code)
        # NOTE(catseye): We include the original and target URLs in error messages for debugging.
        # These messages are not executed or evaluated. The redirect decision is made above.
        raise DNSError.new("External redirect blocked: #{target_url} (from #{original_url})")
      end

      def resolve(redirect_url : String, original_url : String) : String
        if redirect_url.starts_with?("http://") || redirect_url.starts_with?("https://")
          redirect_url
        else
          base = URI.parse(original_url)
          relative = URI.parse(redirect_url)
          resolved = base.resolve(relative)
          raise URI::Error.new("Failed to resolve redirect URL: #{redirect_url} from #{original_url}") unless resolved.host
          resolved.to_s
        end
      rescue ex : URI::Error
        raise ex
      rescue ex
        raise URI::Error.new("Invalid redirect URL: #{redirect_url} (#{ex.class}: #{ex.message})")
      end

      def allow?(source_domain : String, target_domain : String, status_code : Int32 = 302) : Bool
        return true if same_domain?(source_domain, target_domain)
        return true if subdomain?(source_domain, target_domain)
        return true if external_allowed?(target_domain, status_code)
        return true if allowed_domain?(source_domain, target_domain)
        return true if same_registrable_domain?(source_domain, target_domain)
        false
      end

      private def same_domain?(source : String, target : String) : Bool
        source == target
      end

      # Allow subdomain <> parent-domain redirects in either direction.
      private def subdomain?(source : String, target : String) : Bool
        target.ends_with?(".#{source}") || source.ends_with?(".#{target}")
      end

      # Check if external redirects are allowed based on config
      private def external_allowed?(target : String, status_code : Int32) : Bool
        redirect_config = @config.redirect
        return true if redirect_config.allow_external
        return true if redirect_config.allow_permanent_external && permanent?(status_code)
        false
      end

      # Permanent redirects (301/308) are trusted for feed fetching
      private def permanent?(status_code : Int32) : Bool
        status_code == 301 || status_code == 308
      end

      # Check if target is in the allowed_domains list
      private def allowed_domain?(source : String, target : String) : Bool
        return false unless allowed = @config.redirect.allowed_domains
        allowed.includes?(target) || allowed.any? { |domain| target.ends_with?(".#{domain}") }
      end

      # Allow if both hosts share the same registrable domain (eTLD+1)
      private def same_registrable_domain?(source : String, target : String) : Bool
        src_reg = PublicSuffix.registrable_domain(source)
        tgt_reg = PublicSuffix.registrable_domain(target)
        return false unless src_reg && tgt_reg
        src_reg == tgt_reg
      rescue
        false
      end
    end
  end
end
