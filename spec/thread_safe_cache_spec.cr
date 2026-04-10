require "spec"
require "../src/fetcher/thread_safe_cache"

describe Fetcher::ThreadSafeCache do
  describe "#get_or_compute" do
    it "computes and caches a value" do
      cache = Fetcher::ThreadSafeCache(String, Int32).new
      call_count = 0

      result = cache.get_or_compute("key1") do
        call_count += 1
        42
      end

      result.should eq(42)
      call_count.should eq(1)

      cached_result = cache.get_or_compute("key1") do
        call_count += 1
        99
      end

      cached_result.should eq(42)
      call_count.should eq(1)
    end

    it "allows concurrent reads of different keys" do
      cache = Fetcher::ThreadSafeCache(String, Int32).new
      compute_times = {} of String => Time::Span
      mutex = Mutex.new

      10.times do |i|
        spawn do
          key = "key#{i}"
          elapsed = Time.measure do
            cache.get_or_compute(key) do
              sleep(50.milliseconds)
              i * 10
            end
          end
          mutex.synchronize { compute_times[key] = elapsed }
        end
      end

      sleep(200.milliseconds)

      mutex.synchronize do
        compute_times.size.should eq(10)
        compute_times.each_value do |elapsed|
          elapsed.should be < 150.milliseconds
        end
      end
    end

    it "coalesces concurrent requests for the same key" do
      cache = Fetcher::ThreadSafeCache(String, Int32).new
      compute_count = 0
      mutex = Mutex.new
      results = [] of Int32
      results_mutex = Mutex.new
      barrier = Channel(Nil).new

      5.times do
        spawn do
          barrier.receive
          result = cache.get_or_compute("same_key") do
            mutex.synchronize { compute_count += 1 }
            sleep(100.milliseconds)
            123
          end
          results_mutex.synchronize { results << result }
        end
      end

      sleep(10.milliseconds)
      5.times { barrier.send(nil) }

      sleep(200.milliseconds)

      results.size.should eq(5)
      results.uniq.should eq([123])
      mutex.synchronize { compute_count.should eq(1) }
    end

    it "handles errors and allows retry" do
      cache = Fetcher::ThreadSafeCache(String, Int32).new
      attempt_count = 0
      mutex = Mutex.new
      results = Channel(Int32).new

      spawn do
        cache.get_or_compute("error_key") do
          mutex.synchronize { attempt_count += 1 }
          if attempt_count == 1
            raise "First attempt failed"
          end
          42
        end
      rescue
        results.send(-1)
      else
        results.send(42)
      end

      sleep(10.milliseconds)

      spawn do
        cache.get_or_compute("error_key") do
          mutex.synchronize { attempt_count += 1 }
          42
        end
      rescue
        results.send(-1)
      else
        results.send(42)
      end

      first_result = results.receive
      second_result = results.receive

      first_result.should eq(-1)
      second_result.should eq(42)
    end
  end

  describe "#size" do
    it "returns total size across all stripes" do
      cache = Fetcher::ThreadSafeCache(String, Int32).new

      100.times do |i|
        cache.get_or_compute("key#{i}") { i }
      end

      cache.size.should eq(100)
    end
  end

  describe "#has_key?" do
    it "checks if key exists in correct stripe" do
      cache = Fetcher::ThreadSafeCache(String, Int32).new

      cache.get_or_compute("present") { 1 }

      cache.has_key?("present").should be_true
      cache.has_key?("absent").should be_false
    end
  end

  describe "#delete" do
    it "removes key from cache" do
      cache = Fetcher::ThreadSafeCache(String, Int32).new
      compute_count = 0

      cache.get_or_compute("delete_me") { compute_count += 1; 1 }
      cache.has_key?("delete_me").should be_true

      cache.delete("delete_me").should be_true
      cache.has_key?("delete_me").should be_false

      cache.get_or_compute("delete_me") { compute_count += 1; 2 }
      compute_count.should eq(2)
    end
  end

  describe "#clear" do
    it "removes all entries" do
      cache = Fetcher::ThreadSafeCache(String, Int32).new

      50.times do |i|
        cache.get_or_compute("key#{i}") { i }
      end

      cache.size.should eq(50)
      cache.clear
      cache.size.should eq(0)
    end
  end

  describe "stripe distribution" do
    it "distributes keys across stripes" do
      cache = Fetcher::ThreadSafeCache(String, Int32).new

      1000.times do |i|
        cache.get_or_compute("key#{i}") { i }
      end

      cache.size.should eq(1000)
    end
  end

  describe "stress test" do
    it "handles high concurrency" do
      cache = Fetcher::ThreadSafeCache(String, Int32).new
      operations = 1000
      completed = Channel(Nil).new
      errors = Channel(Exception).new

      operations.times do |i|
        spawn do
          key = "key#{i % 50}"
          begin
            cache.get_or_compute(key) do
              sleep(rand(1..5).milliseconds)
              i
            end
            completed.send(nil)
          rescue ex
            errors.send(ex)
          end
        end
      end

      operations.times do
        select
        when completed.receive
        when ex = errors.receive
          fail "Unexpected error: #{ex.message}"
        end
      end
    end
  end
end
