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

    def debug_verify_dns_rebinding(url : String) : Nil
      verify_dns_rebinding(url)
    end

    # Test helper to verify allow_redirect? behaviour for unit tests
    def debug_allow_redirect?(source_domain : String, target_domain : String) : Bool
      allow_redirect?(source_domain, target_domain)
    end

    # Test helper to exercise check_ssrf() without needing a full request
    def debug_check_ssrf(url : String) : Nil
      check_ssrf(url)
    end

    # Test helper to exercise validate_redirect_target() directly
    def debug_validate_redirect_target(url : String) : Nil
      validate_redirect_target(url)
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

    # Test helper to expose extract_redirect_url
    def debug_extract_redirect_url(response)
      # If a Hash was passed (test-only), call the headers-based helper directly.
      if response.is_a?(Hash)
        extract_redirect_url_from_headers(response.as(Hash(String, String | Array(String))))
      else
        extract_redirect_url(response)
      end
    end
  end
end
