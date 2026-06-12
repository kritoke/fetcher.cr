require "../../src/fetcher"

# Test-only helpers: reopen the class within spec/ to expose test helpers without
# polluting production source. Files under spec/ are only loaded by the test
# runner.

module Fetcher
  class CrestHttpClient
    # Expose limited DNS cache access for tests
    def debug_get_cached_dns(host : String) : Socket::IPAddress?
      get_cached_dns(host)
    end

    def debug_clear_dns_cache : Nil
      clear_dns_cache
    end

    # Test helper to exercise the rebinding checker's verify method
    def debug_verify_dns_rebinding(url : String) : Nil
      @rebinding_checker.verify(url)
    end

    # Test helper to verify the redirect policy's allow? behaviour for unit tests
    def debug_allow_redirect?(source_domain : String, target_domain : String, status_code : Int32 = 302) : Bool
      @policy.allow?(source_domain, target_domain, status_code)
    end

    # Test helper to exercise check_ssrf() without needing a full request
    def debug_check_ssrf(url : String) : Nil
      check_ssrf(url)
    end

    # Test helper to exercise the redirect policy's validate_target() directly
    def debug_validate_redirect_target(url : String) : Nil
      @policy.validate_target(url)
    end

    # Test helper to seed the DNS cache for network-free tests
    def debug_seed_dns_cache(host : String, ip_str : String, port : Int32 = 80) : Nil
      return unless @config.dns.cache_enabled
      # Parse IP:port format (e.g., "93.184.216.34:80") or just IP (e.g., "93.184.216.34")
      if ip_str.includes?(":")
        parts = ip_str.split(":")
        ip = Socket::IPAddress.new(parts[0], parts[1]?.try(&.to_i) || port)
      else
        ip = Socket::IPAddress.new(ip_str, port)
      end
      cache_dns(host, ip)
    rescue
      # If parsing fails, try as-is (for IPv6 or other formats)
      ip = Socket::IPAddress.new(ip_str.split(":")[0], port)
      cache_dns(host, ip)
    end

    # Test helper to expose the redirect policy's extract_url methods
    def debug_extract_redirect_url(response)
      # If a Hash was passed (test-only), call the headers-based helper directly.
      if response.is_a?(Hash)
        @policy.extract_url_from_headers(response.as(Hash(String, String | Array(String))))
      else
        @policy.extract_url(response)
      end
    end

    # Test helper for fetcherc-c1h.11: preflight_redirect_target must only
    # consult the target's circuit breaker; it must NOT call record_success
    # on the target (success recording happens in perform_follow_redirect
    # after the redirected request actually returns).
    def debug_preflight_redirect_target(from_domain : String, to_domain : String) : Nil
      preflight_redirect_target(from_domain, to_domain)
    end
  end
end
