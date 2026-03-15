module Fetcher
  # Memory pool for reusable buffers to reduce GC pressure
  module BufferPool
    @@pool = Hash(Symbol, Deque(Bytes)).new
    @@lock = Mutex.new
    @@stats = Hash(Symbol, {hits: Int64, misses: Int64, allocated: Int64}).new

    DEFAULT_POOL_SIZES = {
      small:  4096,
      medium: 16384,
      large:  65536,
    }

    def self.get(size : Int) : Bytes
      category = categorize_size(size)
      buffer = nil

      @@lock.synchronize do
        if @@pool[category]? && !@@pool[category].empty?
          buffer = @@pool[category].shift
          @@stats[category][:hits] += 1
        else
          @@stats[category][:misses] += 1
          @@stats[category][:allocated] += 1
        end
      end

      buffer || Bytes.new(size)
    end

    def self.return(buffer : Bytes)
      return if buffer.empty?
      category = categorize_size(buffer.size)

      @@lock.synchronize do
        queue = (@@pool[category] ||= Deque(Bytes).new)
        if queue.size < 100
          queue << buffer
        end
      end
    end

    def self.stats
      @@lock.synchronize do
        @@stats.dup
      end
    end

    def self.reset
      @@lock.synchronize do
        @@pool.clear
      end
    end

    private def self.categorize_size(size : Int) : Symbol
      case size
      when ..4096    then :small
      when ..16384   then :medium
      else                :large
      end
    end
  end

  # Optimized buffer for streaming with pooling
  class PooledBuffer
    getter bytes : Bytes
    getter capacity : Int

    def initialize(size : Int = 16384)
      @capacity = size
      @bytes = BufferPool.get(size)
    end

    def resize(new_size : Int)
      return if new_size <= @capacity
      BufferPool.return(@bytes)
      @capacity = new_size
      @bytes = BufferPool.get(new_size)
    end

    def reset
      @bytes = @bytes[0, 0]
    end

    def finalize
      BufferPool.return(@bytes)
    end
  end
end
