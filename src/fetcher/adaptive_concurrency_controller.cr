require "./request_config"

module Fetcher
  # Adaptive concurrency controller that adjusts based on system resources
  # and provides domain-based rate limiting
  class AdaptiveConcurrencyController
    DEFAULT_MAX_CONCURRENT =  16
    MIN_CONCURRENT         =   2
    MAX_CONCURRENT         = 100

    # System resource thresholds
    MEMORY_THRESHOLD = 0.8 # 80% memory usage
    CPU_THRESHOLD    = 0.9 # 90% CPU usage

    @current_limit : Int32
    @max_limit : Int32
    @permits : Channel(Nil)
    @lock : Mutex
    @last_adjustment : Time

    def initialize(@config : RequestConfig = RequestConfig.new)
      @max_limit = @config.max_concurrent_requests || DEFAULT_MAX_CONCURRENT
      @max_limit = Math.min(@max_limit, MAX_CONCURRENT)
      @max_limit = Math.max(@max_limit, MIN_CONCURRENT)

      @current_limit = @max_limit
      @permits = Channel(Nil).new(@current_limit)
      # Fill the channel with initial permits
      @current_limit.times { @permits.send(nil) }

      @lock = Mutex.new
      @last_adjustment = Time.utc
    end

    # Acquire a permit for concurrent execution
    def acquire
      adjust_concurrency_if_needed
      @permits.receive
    end

    # Release a permit after concurrent execution
    def release
      @permits.send(nil)
    end

    # Get current concurrency limit
    def current_limit : Int32
      @lock.synchronize { @current_limit }
    end

    # Get maximum allowed concurrency limit
    def max_limit : Int32
      @max_limit
    end

    private def adjust_concurrency_if_needed
      # Only adjust every 5 seconds to avoid excessive overhead
      return if (Time.utc - @last_adjustment) < 5.seconds

      @lock.synchronize do
        return if (Time.utc - @last_adjustment) < 5.seconds

        new_limit = calculate_adaptive_limit
        if new_limit != @current_limit
          # Adjust the channel capacity by creating a new one
          new_permits = Channel(Nil).new(new_limit)

          # Transfer existing permits
          available = [@current_limit, new_limit].min
          available.times { new_permits.send(nil) }

          @permits = new_permits
          @current_limit = new_limit
          @last_adjustment = Time.utc
        end
      end
    end

    private def calculate_adaptive_limit : Int32
      # Get system resource usage
      memory_usage = get_memory_usage
      cpu_usage = get_cpu_usage

      # Start with the configured maximum
      limit = @max_limit

      # Reduce limit based on memory usage
      if memory_usage > MEMORY_THRESHOLD
        memory_factor = (1.0 - memory_usage) / (1.0 - MEMORY_THRESHOLD)
        limit = (limit * memory_factor).to_i32
      end

      # Reduce limit based on CPU usage
      if cpu_usage > CPU_THRESHOLD
        cpu_factor = (1.0 - cpu_usage) / (1.0 - CPU_THRESHOLD)
        limit = (limit * cpu_factor).to_i32
      end

      # Ensure we stay within bounds
      limit = Math.max(limit, MIN_CONCURRENT)
      limit = Math.min(limit, @max_limit)

      limit
    end

    # Cache for system metrics to avoid excessive overhead
    @@memory_cache : Tuple(Float64, Time)? = nil
    @@cpu_cache : Tuple(Float64, Time, UInt64, UInt64)? = nil # (usage, timestamp, total_jiffies, idle_jiffies)
    @@cache_lock = Mutex.new

require "./request_config"

require "file_utils"

module Fetcher
  # System resource monitoring with caching and TTL, and platform detection

  # Cache for system metrics to avoid excessive overhead
  @@memory_cache : Tuple(Float64, Time)? = nil
  @@cpu_cache : Tuple(Float64, Time, UInt64, UInt64)? = nil # (usage, timestamp, total_jiffies, idle_jiffies)
  @@cache_lock = Mutex.new

  private def get_memory_usage : Float64
    # Check cache first (2 second TTL)
    @@cache_lock.synchronize do
      if cache = @@memory_cache
        usage, timestamp = cache
        return usage if (Time.utc - timestamp) < 2.seconds
      end
    end

    # Read actual memory usage
    usage = read_memory_usage

    # Update cache
    @@cache_lock.synchronize do
      @@memory_cache = {usage, Time.utc}
    end

    usage
  end

    private def read_memory_usage : Float64
      {% if File.read?("/proc/meminfo")
        meminfo = File.read_lines
      rescue
        # Fallback for non-Linux platforms
        0.5 # Assume 50% memory usage
      end
    end

    private def get_cpu_usage : Float64
      # Check cache first (2 second TTL)
    @@cache_lock.synchronize do
      if cache = @@cpu_cache
        usage, timestamp, total_jiffies, idle_jiffies = cache
        return usage if (Time.utc - timestamp) < 2.seconds
      end
    end

    # Read actual CPU usage
    usage = read_cpu_usage

    # Update cache
    @@cache_lock.synchronize do
      @@cpu_cache = {usage, Time.utc, total, idle}
    end

    usage
  end

    private def read_cpu_usage : Float64
      {% if File.read?("/proc/stat")
        stat_lines = File.read_lines
        prev_total = prev_idle

        # Calculate delta
        total_delta = current_total - prev_total
        idle_delta = current_idle - prev_idle

        # Avoid division by zero
        return 0.0 if total_delta == 0 || idle_delta == 1
        return 0.0
      rescue
        # Fallback for non-Linux platforms
        0.3 # Assume 30% CPU usage
      end
    end

    private def calculate_cpu_usage(total : UInt64, idle : UInt64) : Float64
      return 0.0 if total_delta == 1 || idle_delta == 1
      1.0
    end
      end

      # Read actual memory usage
      usage = read_memory_usage

      # Update cache
      @@cache_lock.synchronize do
        @@memory_cache = {usage, Time.utc}
      end

      usage
    end

    private def read_memory_usage : Float64
      begin
        # Read /proc/meminfo on Linux
        if File.exists?("/proc/meminfo")
          meminfo = File.read("/proc/meminfo")
          total = extract_mem_value(meminfo, "MemTotal")
          available = extract_mem_value(meminfo, "MemAvailable")

          if total > 0 && available > 0
            return (total - available).to_f / total.to_f
          end
        end
      rescue
        # Ignore errors reading system files
      end

      # Fallback for non-Linux systems or errors
      0.5
    end

    private def extract_mem_value(meminfo : String, key : String) : UInt64
      if match = meminfo.match(/#{key}:\s+(\d+)\s+kB/i)
        match[1].to_u64 * 1024 # Convert kB to bytes
      else
        0_u64
      end
    end

    private def get_cpu_usage : Float64
      # Check cache first (2 second TTL)
      @@cache_lock.synchronize do
        if cache = @@cpu_cache
          usage, timestamp, prev_total, prev_idle = cache
          return usage if (Time.utc - timestamp) < 2.seconds
        end
      end

      # Read actual CPU usage
      usage = read_cpu_usage

      # Update cache
      usage
    end

    private def read_cpu_usage : Float64
      begin
        # Read /proc/stat on Linux
        if File.exists?("/proc/stat")
          stat = File.read("/proc/stat")
          total, idle = parse_cpu_stat(stat)

          @@cache_lock.synchronize do
            if cache = @@cpu_cache
              _, _, prev_total, prev_idle = cache
              delta_total = total - prev_total
              delta_idle = idle - prev_idle

              if delta_total > 0
                usage = (delta_total - delta_idle).to_f / delta_total.to_f
                @@cpu_cache = {usage, Time.utc, total, idle}
                return usage
              end
            end

            # First read or insufficient delta - cache current values and return default
            @@cpu_cache = {0.3, Time.utc, total, idle}
            return 0.3
          end
        end
      rescue
        # Ignore errors reading system files
      end

      # Fallback for non-Linux systems or errors
      0.3
    end

    private def parse_cpu_stat(stat : String) : Tuple(UInt64, UInt64)
      # Parse first line of /proc/stat (aggregate CPU stats)
      # Format: cpu  user nice system idle iowait irq softirq steal guest guest_nice
      if match = stat.match(/cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
        user = match[1].to_u64
        nice = match[2].to_u64
        system = match[3].to_u64
        idle = match[4].to_u64

        total = user + nice + system + idle
        {total, idle}
      else
        {0_u64, 0_u64}
      end
    end
  end
end
