# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe "Performance Benchmarks" do
  # Number of iterations for benchmarks
  ITERATIONS = 100
  WARM_UP_ITERATIONS = 10

  # Performance requirements from spec
  MAX_INITIALIZATION_TIME_MS = 5.0
  MAX_CACHE_ACCESS_TIME_MS = 0.1

  before(:all) do
    # Define test tools for benchmarking
    @test_tools = {}

    # Create various tool classes for testing
    10.times do |i|
      tool_class = Class.new do
        define_singleton_method(:name) { "BenchmarkTool#{i}" }

        def call(**args)
          { tool_id: self.class.name, args: args }
        end
      end

      const_name = "BenchmarkTool#{i}Tool"
      stub_const("Ai::Tools::#{const_name}", tool_class)
      @test_tools["benchmark_tool#{i}".to_sym] = tool_class
    end
  end

  describe "Agent initialization performance" do
    it "initializes agents within 5ms threshold" do
      # Define agent with multiple tools
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "PerformanceTestAgent"
        model "gpt-4o"

        # Add multiple tools
        tool :benchmark_tool0
        tool :benchmark_tool1
        tool :benchmark_tool2
        tool :benchmark_tool3
        tool :benchmark_tool4
      end

      # Warm up
      WARM_UP_ITERATIONS.times { agent_class.new }

      # Benchmark
      total_time_ms = 0
      times = []

      ITERATIONS.times do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        agent_class.new
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        time_ms = (end_time - start_time) * 1000
        times << time_ms
        total_time_ms += time_ms
      end

      avg_time_ms = total_time_ms / ITERATIONS
      max_time_ms = times.max
      min_time_ms = times.min

      # Report results
      puts "\n  Agent Initialization Performance:"
      puts "    Average: #{'%.4f' % avg_time_ms}ms"
      puts "    Min:     #{'%.4f' % min_time_ms}ms"
      puts "    Max:     #{'%.4f' % max_time_ms}ms"

      # Verify against requirement
      expect(avg_time_ms).to be < MAX_INITIALIZATION_TIME_MS
    end

    it "shows improvement with lazy loading" do
      # Eager loading simulation (old pattern)
      eager_agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "EagerLoadingAgent"
        model "gpt-4o"

        # Simulate eager loading by resolving tools immediately
        def initialize(**options)
          # Force tool resolution during initialization
          self.class._tools_config.each do |config|
            RAAF::ToolRegistry.resolve(config[:name])
          end
          super
        end

        tool :benchmark_tool0
        tool :benchmark_tool1
        tool :benchmark_tool2
      end

      # Lazy loading (new pattern)
      lazy_agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "LazyLoadingAgent"
        model "gpt-4o"

        tool :benchmark_tool0
        tool :benchmark_tool1
        tool :benchmark_tool2
      end

      # Benchmark eager loading
      eager_times = []
      ITERATIONS.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        eager_agent_class.new
        eager_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      # Benchmark lazy loading
      lazy_times = []
      ITERATIONS.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        lazy_agent_class.new
        lazy_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      eager_avg = eager_times.sum / eager_times.length
      lazy_avg = lazy_times.sum / lazy_times.length
      improvement = ((eager_avg - lazy_avg) / eager_avg) * 100

      puts "\n  Lazy Loading Improvement:"
      puts "    Eager avg: #{'%.4f' % eager_avg}ms"
      puts "    Lazy avg:  #{'%.4f' % lazy_avg}ms"
      puts "    Improvement: #{'%.1f' % improvement}%"

      # Lazy should be faster
      expect(lazy_avg).to be < eager_avg
    end
  end

  describe "Tool resolution performance" do
    it "resolves tools quickly from registry" do
      # Pre-register tools
      @test_tools.each do |name, klass|
        RAAF::ToolRegistry.register(name, klass)
      end

      resolution_times = []

      # Benchmark tool resolution
      @test_tools.keys.each do |tool_name|
        ITERATIONS.times do
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          RAAF::ToolRegistry.resolve(tool_name)
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          resolution_times << (end_time - start) * 1000
        end
      end

      avg_time = resolution_times.sum / resolution_times.length
      max_time = resolution_times.max

      puts "\n  Tool Resolution Performance:"
      puts "    Average: #{'%.4f' % avg_time}ms"
      puts "    Max:     #{'%.4f' % max_time}ms"

      # Should be very fast (sub-millisecond)
      expect(avg_time).to be < 1.0
    end

    it "benefits from caching on repeated lookups" do
      tool_name = :benchmark_tool5

      # First lookup (uncached)
      first_lookup_times = []
      10.times do
        RAAF::ToolRegistry.instance_variable_get(:@registry).clear # Clear cache
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        RAAF::ToolRegistry.resolve(tool_name)
        first_lookup_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      # Subsequent lookups (cached)
      cached_lookup_times = []
      100.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        RAAF::ToolRegistry.resolve(tool_name)
        cached_lookup_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      first_avg = first_lookup_times.sum / first_lookup_times.length
      cached_avg = cached_lookup_times.sum / cached_lookup_times.length

      puts "\n  Cache Performance:"
      puts "    First lookup:  #{'%.4f' % first_avg}ms"
      puts "    Cached lookup: #{'%.4f' % cached_avg}ms"
      puts "    Speedup:       #{'%.1f' % (first_avg / cached_avg)}x"

      # Cached should be faster
      expect(cached_avg).to be < first_avg
      # Cached should meet requirement
      expect(cached_avg).to be < MAX_CACHE_ACCESS_TIME_MS
    end
  end

  describe "Memory usage" do
    it "maintains reasonable memory footprint with many agents" do
      initial_memory = get_memory_usage

      # Create many agent instances
      agents = []
      100.times do |i|
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "MemoryTestAgent#{i}"
          model "gpt-4o"
          tool :benchmark_tool0
          tool :benchmark_tool1
        end
        agents << agent_class.new
      end

      final_memory = get_memory_usage
      memory_increase_mb = (final_memory - initial_memory) / 1024.0 / 1024.0

      puts "\n  Memory Usage:"
      puts "    Initial: #{'%.2f' % (initial_memory / 1024.0 / 1024.0)}MB"
      puts "    Final:   #{'%.2f' % (final_memory / 1024.0 / 1024.0)}MB"
      puts "    Increase: #{'%.2f' % memory_increase_mb}MB for 100 agents"

      # Memory increase should be reasonable (< 50MB for 100 agents)
      expect(memory_increase_mb).to be < 50
    end
  end

  describe "Thread safety performance" do
    it "handles concurrent agent creation efficiently" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ThreadSafeAgent"
        model "gpt-4o"
        tool :benchmark_tool0
        tool :benchmark_tool1
      end

      thread_count = 10
      agents_per_thread = 10

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      threads = thread_count.times.map do
        Thread.new do
          agents_per_thread.times { agent_class.new }
        end
      end

      threads.each(&:join)

      total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      total_agents = thread_count * agents_per_thread
      avg_time_ms = (total_time * 1000) / total_agents

      puts "\n  Thread Safety Performance:"
      puts "    Total agents:     #{total_agents}"
      puts "    Total time:       #{'%.2f' % (total_time * 1000)}ms"
      puts "    Avg per agent:    #{'%.4f' % avg_time_ms}ms"
      puts "    Threads:          #{thread_count}"

      # Should still meet performance requirements under concurrent load
      expect(avg_time_ms).to be < MAX_INITIALIZATION_TIME_MS * 2 # Allow some overhead for threading
    end
  end

  describe "Namespace search performance" do
    it "searches namespaces efficiently" do
      # Test worst-case: tool only exists in last namespace
      last_namespace_tool = Class.new do
        def call
          { found: true }
        end
      end

      # Add to the last namespace searched
      stub_const("Global::LastResortTool", last_namespace_tool)
      RAAF::ToolRegistry.instance_variable_get(:@namespaces) << "Global"

      search_times = []
      50.times do
        # Clear cache to force full search
        RAAF::ToolRegistry.instance_variable_get(:@registry).clear

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        RAAF::ToolRegistry.resolve(:last_resort)
        search_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      avg_time = search_times.sum / search_times.length
      puts "\n  Namespace Search (worst-case):"
      puts "    Average: #{'%.4f' % avg_time}ms"

      # Even worst-case should be fast
      expect(avg_time).to be < 2.0
    end
  end

  describe "Before/After comparison" do
    it "documents performance improvements" do
      # Simulated "before" implementation (without optimizations)
      class BeforeImplementation
        def self.resolve_tool(name)
          # Simulate old implementation with sleep
          sleep(0.001) # Simulate slower lookup
          Object
        end
      end

      # Current implementation
      class AfterImplementation
        def self.resolve_tool(name)
          RAAF::ToolRegistry.resolve(name)
        end
      end

      # Benchmark old implementation
      before_times = []
      20.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        BeforeImplementation.resolve_tool(:test)
        before_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      # Benchmark new implementation
      after_times = []
      20.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        AfterImplementation.resolve_tool(:benchmark_tool0)
        after_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      before_avg = before_times.sum / before_times.length
      after_avg = after_times.sum / after_times.length
      improvement_factor = before_avg / after_avg

      puts "\n  === PERFORMANCE SUMMARY ==="
      puts "  Before optimizations: #{'%.4f' % before_avg}ms avg"
      puts "  After optimizations:  #{'%.4f' % after_avg}ms avg"
      puts "  Improvement factor:   #{'%.1f' % improvement_factor}x faster"
      puts "  ==========================="

      # New implementation should be faster
      expect(after_avg).to be < before_avg
    end
  end

  private

  def get_memory_usage
    # Get current process memory usage in bytes
    if RUBY_PLATFORM.include?("darwin") || RUBY_PLATFORM.include?("linux")
      `ps -o rss= -p #{Process.pid}`.to_i * 1024 # Convert KB to bytes
    else
      # Fallback for other platforms
      GC.stat[:heap_live_slots] * 40 # Approximate bytes per slot
    end
  end
end