require "set"

module Fetcher
  module PublicSuffix
    @@rules_loaded : Bool = false
    @@rules_lock = Mutex.new
    @@exact : Set(String) = Set(String).new
    @@wildcard : Set(String) = Set(String).new
    @@exception : Set(String) = Set(String).new

    def self.load_rules : Nil
      @@rules_lock.synchronize do
        return if @@rules_loaded
        @@exact.clear
        @@wildcard.clear
        @@exception.clear

        path = File.join(File.dirname(__FILE__), "public_suffix_list.dat")
        begin
          text = File.read(path)
        rescue ex
          # Fallback minimal rules if file is missing
          text = "// Minimal fallback public suffix rules\ncom\norg\nnet\nio\nco.uk\nuk\nco\nblogspot.com\n"
        end

        text.each_line do |line|
          line = line.strip
          next if line.empty? || line.starts_with?("//")
          if line.starts_with?("!")
            @@exception.add(line[1..-1])
          elsif line.starts_with?("*.")
            @@wildcard.add(line[2..-1])
          else
            @@exact.add(line)
          end
        end

        @@rules_loaded = true
      end
    end

    def self.get_public_suffix(domain : String) : String
      load_rules
      domain = domain.downcase
      labels = domain.split('.')
      matches = [] of String

      # Build suffix incrementally to avoid O(n^2) string allocation
      suffix_parts = [] of String
      (labels.size - 1).step(to: 0, by: -1) do |start|
        suffix = labels[start..-1].join('.')
        suffix_parts.unshift(suffix)

        if @@exception.includes?(suffix)
          matches << "!#{suffix}"
        end
        if @@exact.includes?(suffix)
          matches << suffix
        end
        if start > 0 && @@wildcard.includes?(labels[start + 1..-1].join('.'))
          matches << "*.#{labels[start + 1..-1].join('.')}"
        end
      end

      if matches.empty?
        public_suffix = labels.last
      else
        # choose longest match by label count
        best = matches.max_by { |m| m.split('.').size }
        if best.starts_with?("!")
          rule = best[1..-1]
          parts = rule.split('.')
          public_suffix = parts[1..-1].join('.')
        elsif best.starts_with?("*.")
          public_suffix = best[2..-1]
        else
          public_suffix = best
        end
      end

      public_suffix
    end

    # Return the registrable domain (eTLD+1) or nil if cannot be determined
    def self.registrable_domain(domain : String) : String?
      return nil if domain.nil? || domain.empty?
      domain = domain.downcase
      # IP addresses: return as-is
      return domain if domain.match(%r{^\d+\.\d+\.\d+\.\d+$})

      labels = domain.split('.')
      return domain if labels.size == 1

      public_suffix = get_public_suffix(domain)
      ps_labels = public_suffix.split('.')

      if labels.size <= ps_labels.size
        return domain
      end

      idx = labels.size - ps_labels.size - 1
      registered = labels[idx..-1].join('.')
      registered
    rescue
      nil
    end
  end
end
