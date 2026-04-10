require "mutex"

module Fetcher
  class ThreadSafeCache(K, V)
    STRIPE_COUNT = 16

    @stripes : Array(Stripe(K, V))

    def initialize
      @stripes = Array(Stripe(K, V)).new(STRIPE_COUNT) { Stripe(K, V).new }
    end

    def get_or_compute(key : K, &block : -> V) : V
      stripe_for(key).get_or_compute(key, &block)
    end

    def size : Int32
      @stripes.sum(&.size)
    end

    def clear : Nil
      @stripes.each(&.clear)
    end

    def has_key?(key : K) : Bool
      stripe_for(key).has_key?(key)
    end

    def delete(key : K) : Bool
      stripe_for(key).delete(key)
    end

    private def stripe_for(key : K) : Stripe(K, V)
      @stripes[key.hash.abs % STRIPE_COUNT]
    end

    private class Stripe(K, V)
      @mutex : Mutex
      @data : Hash(K, V)
      @computing : Hash(K, Deque(Fiber))

      def initialize
        @mutex = Mutex.new
        @data = Hash(K, V).new
        @computing = Hash(K, Deque(Fiber)).new
      end

      def size : Int32
        @mutex.synchronize { @data.size }
      end

      def clear : Nil
        @mutex.synchronize { @data.clear }
      end

      def has_key?(key : K) : Bool
        @mutex.synchronize { @data.has_key?(key) }
      end

      def delete(key : K) : Bool
        @mutex.synchronize { @data.delete(key) != nil }
      end

      def get_or_compute(key : K, &block : -> V) : V
        wait_fiber = nil

        @mutex.synchronize do
          return @data[key] if @data.has_key?(key)

          if waiters = @computing[key]?
            wait_fiber = Fiber.current
            waiters << wait_fiber
          else
            @computing[key] = Deque(Fiber).new
          end
        end

        if wait_fiber
          Fiber.suspend
          @mutex.synchronize do
            if val = @data[key]?
              return val
            end
          end
          compute_and_store(key, &block)
        else
          compute_and_store(key, &block)
        end
      end

      private def compute_and_store(key : K, & : -> V) : V
        result = yield

        @mutex.synchronize do
          @data[key] = result
          if waiters = @computing.delete(key)
            waiters.each(&.enqueue)
          end
        end

        result
      rescue ex
        computation_failed(key)
        raise ex
      end

      private def computation_failed(key : K) : Nil
        @mutex.synchronize do
          @computing.delete(key)
        end
      end

      private def wake_waiting_fibers(key : K, ex : Exception?) : Nil
        @mutex.synchronize do
          if waiters = @computing.delete(key)
            waiters.each(&.enqueue)
          end
        end
      end
    end
  end
end
