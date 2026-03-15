require "http/client"

module Fetcher
  # Connection pool for efficient HTTP connection reuse
  module ConnectionPool
    class PooledConnection
      getter client : HTTP::Client
      getter domain : String
      @last_used : Time

      def initialize(@client : HTTP::Client, @domain : String)
        @last_used = Time.utc
      end

      def mark_used
        @last_used = Time.utc
      end

      def idle_time_ms
        (Time.utc - @last_used).total_milliseconds
      end
    end

    @@pools = Hash(String, Array(PooledConnection)).new
    @@lock = Mutex.new
    @@max_connections_per_domain = 4
    @@connection_timeout = 30_000

    def self.get_connection(domain : String) : HTTP::Client?
      @@lock.synchronize do
        pool = @@pools[domain]?
        return nil unless pool

        conn = pool.find { |c| !c.client.closed? }
        return nil unless conn

        conn.mark_used
        conn.client
      end
    end

    def self.return_connection(domain : String, client : HTTP::Client)
      @@lock.synchronize do
        pool = (@@pools[domain] ||= Array(PooledConnection).new)

        active_count = pool.size
        if active_count < @@max_connections_per_domain
          pool << PooledConnection.new(client, domain)
        else
          client.close
        end
      end
    end

    def self.cleanup_idle(timeout_ms : Int = @@connection_timeout)
      @@lock.synchronize do
        @@pools.each do |domain, pool|
          pool.reject! do |conn|
            idle = conn.idle_time_ms > timeout_ms
            conn.client.close if idle
            idle
          end
        end
        @@pools.reject! { |_, pool| pool.empty? }
      end
    end

    def self.clear
      @@lock.synchronize do
        @@pools.each_value do |pool|
          pool.each { |conn| conn.client.close }
        end
        @@pools.clear
      end
    end

    def self.set_config(max_connections : Int, timeout_ms : Int)
      @@max_connections_per_domain = max_connections
      @@connection_timeout = timeout_ms
    end
  end
end
