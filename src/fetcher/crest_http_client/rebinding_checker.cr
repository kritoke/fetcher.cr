module Fetcher
  class CrestHttpClient
    # DNS rebinding detection extracted from CrestHttpClient.
    # Verifies that resolved IPs haven't changed since validation
    # (the classic DNS rebinding attack). Uses DnsCache for
    # caching validated addresses and the URLValidator for IP checks.
    class RebindingChecker
      def initialize(@config : RequestConfig, @validator : URLValidator::Service)
      end

      def verify(url : String) : Nil
        return unless should_check?

        host = extract_host(url)
        return unless host && valid_host?(host)

        if cached = get_cached_dns(host)
          validate_cached_dns(host, cached)
        else
          resolve_and_validate_new_dns(host)
        end
      rescue ex : DNSError
        raise ex
      rescue ex
        ::Log.for("fetcher").debug { "DNS rebinding check failed for #{host}: #{ex.message}" }
      end

      private def should_check? : Bool
        @config.dns.rebinding_check
      end

      private def extract_host(url : String) : String?
        URI.parse(url).host
      end

      private def valid_host?(host : String?) : Bool
        return false unless host
        !@validator.looks_like_ip?(host)
      end

      private def validate_cached_dns(host : String, cached : Socket::IPAddress) : Nil
        return if @validator.validate_connected_ip(host, cached)
        raise DNSError.new("DNS rebinding detected for #{host}: IP changed after validation")
      end

      private def resolve_and_validate_new_dns(host : String) : Nil
        addr_info = Socket::Addrinfo.resolve(host, URLValidator::DNS_RESOLVE_PORT.to_s, type: Socket::Type::STREAM, protocol: Socket::Protocol::TCP)
        valid_addrs = addr_info.select { |addr| valid_address?(addr) }

        # If no valid addresses found, raise error
        if valid_addrs.empty?
          raise DNSError.new("DNS resolution for #{host} returned no valid IP addresses")
        end

        valid_addrs.each do |addr|
          validate_address_for_host(host, addr)
        end
      end

      private def valid_address?(addr : Socket::Addrinfo) : Bool
        addr.family == Socket::Family::INET || addr.family == Socket::Family::INET6
      end

      private def validate_address_for_host(host : String, addr : Socket::Addrinfo) : Nil
        ip_address = addr.ip_address
        cache_dns(host, ip_address)
        return if @validator.validate_connected_ip(host, ip_address)
        raise DNSError.new("DNS rebinding detected for #{host}: IP changed after validation")
      end

      private def get_cached_dns(host : String) : Socket::IPAddress?
        return unless @config.dns.cache_enabled
        DnsCache.lookup(host)
      end

      private def cache_dns(host : String, addr : Socket::IPAddress) : Nil
        return unless @config.dns.cache_enabled
        DnsCache.store(host, addr, @config.dns.cache_ttl)
      end
    end
  end
end
