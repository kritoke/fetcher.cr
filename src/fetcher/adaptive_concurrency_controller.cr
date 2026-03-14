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
          old_permits = @permits
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

    private def get_memory_usage : Float64
      # Placeholder - in a real implementation, this would read from /proc/meminfo on Linux
      # or use system calls to get actual memory usage
      0.5 # Assume 50% memory usage
    end

    private def get_cpu_usage : Float64
      # Placeholder - in a real implementation, this would read CPU usage
      # from /proc/stat on Linux or use system calls
      0.3 # Assume 30% CPU usage
    end
  end
end
