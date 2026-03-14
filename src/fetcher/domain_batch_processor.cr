require "uri"
require "../fetcher"

module Fetcher
  # Domain-based feed grouping and batch processing
  class DomainBatchProcessor
    def self.group_by_domain(urls : Array(String)) : Hash(String, Array(String))
      groups = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }

      urls.each do |url|
        begin
          uri = URI.parse(url)
          domain = uri.host || "default"
          groups[domain] << url
        rescue ex
          # Invalid URL, group under "invalid"
          groups["invalid"] << url
        end
      end

      groups
    end

    # Process feeds in domain batches with adaptive concurrency
    def self.process_batches(urls : Array(String), headers : ::HTTP::Headers = ::HTTP::Headers.new, limit : Int32 = 100, config : RequestConfig = RequestConfig.new) : Array(Result)
      domain_groups = group_by_domain(urls)
      results = [] of Result

      # Process each domain group sequentially to maximize connection reuse
      domain_groups.each do |domain, domain_urls|
        # Use domain-specific configuration if available
        domain_config = get_domain_config(domain, config)

        # Process all URLs in this domain group
        domain_results = ConcurrentFetcher.pull_multiple(domain_urls, headers, limit, domain_config)
        results.concat(domain_results)
      end

      results
    end

    private def self.get_domain_config(domain : String, base_config : RequestConfig) : RequestConfig
      # In a real implementation, this would look up domain-specific configuration
      # from feeds.yml or other configuration sources
      base_config
    end
  end
end
