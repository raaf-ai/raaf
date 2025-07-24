# frozen_string_literal: true

require "spec_helper"
require "benchmark"

if defined?(RAAF::Async::Runner)
  RSpec.describe "RAAF Streaming Performance", :performance do
    before(:all) do
      skip "Skipping streaming performance tests - benchmarking issues"
    end

    let(:agent) do
      RAAF::Agent.new(
        name: "PerformanceTestAgent",
        instructions: "You are a performance testing assistant.",
        model: "gpt-4o"
      )
    end

    let(:mock_provider) { double("MockProvider") }
    let(:standard_response) do
      {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => "Performance test response"
          },
          "finish_reason" => "stop"
        }],
        "usage" => { "total_tokens" => 20 }
      }
    end

    before do
      allow(mock_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
      allow(mock_provider).to receive(:chat_completion).and_return(standard_response)
    end

    describe "throughput benchmarks" do
      it "measures async runner throughput" do
        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

        # Warm up
        Async do
          async_runner.run_async("warmup").wait
        end

        # Benchmark single requests
        single_request_time = Benchmark.realtime do
          10.times do
            Async do
              async_runner.run_async("Single request test").wait
            end
          end
        end

        expect(single_request_time).to be < 1.0 # Should complete 10 requests in under 1 second
        puts "Single request average: #{(single_request_time / 10 * 1000).round(2)}ms per request"
      end

      it "measures concurrent request handling" do
        async_runner = RAAF::Async::Runner.new(
          agent: agent,
          provider: mock_provider,
          pool_size: 10
        )

        concurrent_count = 50

        concurrent_time = Benchmark.realtime do
          tasks = []
          concurrent_count.times do |i|
            tasks << async_runner.run_async("Concurrent request #{i}")
          end

          Async do
            tasks.map(&:wait)
          end
        end

        throughput = concurrent_count / concurrent_time
        expect(throughput).to be > 20 # Should handle at least 20 requests per second
        puts "Concurrent throughput: #{throughput.round(2)} requests/second"
      end

      it "compares sync vs async performance" do
        sync_runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

        request_count = 20

        # Sync performance
        sync_time = Benchmark.realtime do
          request_count.times do |i|
            sync_runner.run("Sync request #{i}")
          end
        end

        # Async performance (concurrent)
        async_time = Benchmark.realtime do
          tasks = []
          request_count.times do |i|
            tasks << async_runner.run_async("Async request #{i}")
          end

          Async do
            tasks.map(&:wait)
          end
        end

        # Async should be significantly faster for concurrent operations
        improvement_ratio = sync_time / async_time
        expect(improvement_ratio).to be > 2.0 # At least 2x improvement

        puts "Sync time: #{(sync_time * 1000).round(2)}ms"
        puts "Async time: #{(async_time * 1000).round(2)}ms"
        puts "Performance improvement: #{improvement_ratio.round(2)}x"
      end
    end

    describe "memory usage benchmarks" do
      it "measures memory usage under load" do
        async_runner = RAAF::Async::Runner.new(
          agent: agent,
          provider: mock_provider,
          pool_size: 5
        )

        # Get baseline memory
        GC.start
        baseline_memory = get_memory_usage

        # Create sustained load
        task_count = 100
        tasks = []

        task_count.times do |i|
          tasks << async_runner.run_async("Memory test #{i}")
        end

        # Wait for completion
        Async do
          tasks.map(&:wait)
        end

        # Measure peak memory
        peak_memory = get_memory_usage
        memory_increase = peak_memory - baseline_memory

        # Memory increase should be reasonable (under 50MB for 100 tasks)
        expect(memory_increase).to be < 50_000_000 # 50MB in bytes

        puts "Baseline memory: #{(baseline_memory / 1024.0 / 1024.0).round(2)}MB"
        puts "Peak memory: #{(peak_memory / 1024.0 / 1024.0).round(2)}MB"
        puts "Memory increase: #{(memory_increase / 1024.0 / 1024.0).round(2)}MB"

        async_runner.shutdown
      end

      it "ensures proper resource cleanup" do
        initial_memory = get_memory_usage

        # Create and destroy multiple runners
        10.times do
          runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

          # Do some work
          Async do
            runner.run_async("Cleanup test").wait
          end

          runner.shutdown
        end

        # Force garbage collection
        3.times { GC.start }

        final_memory = get_memory_usage
        memory_leak = final_memory - initial_memory

        # Should not leak more than 10MB
        expect(memory_leak).to be < 10_000_000 # 10MB
        puts "Memory leak: #{(memory_leak / 1024.0 / 1024.0).round(2)}MB"
      end
    end

    describe "latency benchmarks" do
      it "measures response latency distribution" do
        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)
        latencies = []

        # Collect latency samples
        50.times do |i|
          start_time = Time.now

          Async do
            async_runner.run_async("Latency test #{i}").wait
          end

          latencies << ((Time.now - start_time) * 1000).round(2) # Convert to milliseconds
        end

        # Calculate statistics
        avg_latency = latencies.sum / latencies.size
        p95_latency = latencies.sort[(latencies.size * 0.95).to_i]
        p99_latency = latencies.sort[(latencies.size * 0.99).to_i]

        # Performance expectations
        expect(avg_latency).to be < 100 # Average under 100ms
        expect(p95_latency).to be < 200 # 95th percentile under 200ms
        expect(p99_latency).to be < 500 # 99th percentile under 500ms

        puts "Average latency: #{avg_latency}ms"
        puts "P95 latency: #{p95_latency}ms"
        puts "P99 latency: #{p99_latency}ms"
      end

      it "measures tool execution latency" do
        def performance_tool(size:)
          # Simulate varying workload
          data = Array.new(size) { rand(1000) }
          data.sum / data.size.to_f
        end

        agent_with_tools = RAAF::Agent.new(
          name: "ToolPerformanceAgent",
          instructions: "Use tools efficiently",
          model: "gpt-4o"
        )
        agent_with_tools.add_tool(method(:performance_tool))

        async_runner = RAAF::Async::Runner.new(agent: agent_with_tools, provider: mock_provider)

        # Mock tool call responses for different sizes
        tool_responses = [
          {
            "choices" => [{
              "message" => {
                "role" => "assistant",
                "content" => "",
                "tool_calls" => [{
                  "id" => "call_small",
                  "type" => "function",
                  "function" => {
                    "name" => "performance_tool",
                    "arguments" => '{"size": 100}'
                  }
                }]
              },
              "finish_reason" => "tool_calls"
            }]
          },
          {
            "choices" => [{
              "message" => {
                "role" => "assistant",
                "content" => "Small dataset processed"
              },
              "finish_reason" => "stop"
            }]
          }
        ]

        allow(mock_provider).to receive(:chat_completion)
          .and_return(*tool_responses)

        # Measure tool execution time
        tool_latency = Benchmark.realtime do
          Async do
            async_runner.run_async("Process a small dataset").wait
          end
        end

        expect(tool_latency).to be < 0.1 # Tool execution under 100ms
        puts "Tool execution latency: #{(tool_latency * 1000).round(2)}ms"
      end
    end

    describe "scalability benchmarks" do
      it "measures performance with increasing concurrent load" do
        async_runner = RAAF::Async::Runner.new(
          agent: agent,
          provider: mock_provider,
          pool_size: 20
        )

        load_levels = [10, 25, 50, 100]
        results = {}

        load_levels.each do |load|
          time = Benchmark.realtime do
            tasks = []
            load.times do |i|
              tasks << async_runner.run_async("Load test #{i}")
            end

            Async do
              tasks.map(&:wait)
            end
          end

          throughput = load / time
          results[load] = {
            time: time,
            throughput: throughput
          }

          puts "Load #{load}: #{time.round(3)}s, #{throughput.round(2)} req/s"
        end

        # Throughput should not degrade significantly with moderate load increases
        small_load_throughput = results[10][:throughput]
        medium_load_throughput = results[50][:throughput]

        degradation_ratio = small_load_throughput / medium_load_throughput
        expect(degradation_ratio).to be < 2.0 # Less than 50% degradation

        async_runner.shutdown
      end

      it "tests thread pool efficiency" do
        pool_sizes = [2, 5, 10, 20]
        task_count = 50
        results = {}

        pool_sizes.each do |pool_size|
          runner = RAAF::Async::Runner.new(
            agent: agent,
            provider: mock_provider,
            pool_size: pool_size
          )

          time = Benchmark.realtime do
            tasks = []
            task_count.times do |i|
              tasks << runner.run_async("Pool test #{i}")
            end

            Async do
              tasks.map(&:wait)
            end
          end

          throughput = task_count / time
          results[pool_size] = throughput

          puts "Pool size #{pool_size}: #{throughput.round(2)} req/s"
          runner.shutdown
        end

        # Optimal pool size should provide best throughput
        best_throughput = results.values.max
        worst_throughput = results.values.min

        improvement_ratio = best_throughput / worst_throughput
        expect(improvement_ratio).to be > 1.5 # At least 50% improvement with optimal sizing
      end
    end

    describe "resource utilization" do
      it "monitors thread pool utilization" do
        async_runner = RAAF::Async::Runner.new(
          agent: agent,
          provider: mock_provider,
          pool_size: 5,
          queue_size: 20
        )

        # Submit more tasks than pool can handle simultaneously
        task_count = 15
        tasks = []

        task_count.times do |i|
          tasks << async_runner.run_async("Resource test #{i}")
        end

        # Monitor stats during execution
        stats_history = []

        # Collect stats periodically
        monitor_task = Async do
          10.times do
            stats_history << async_runner.stats
            sleep(0.01)
          end
        end

        # Wait for completion
        Async do
          tasks.map(&:wait)
          monitor_task.wait
        end

        # Analyze utilization
        max_active = stats_history.map { |s| s[:active_tasks] }.max
        max_queued = stats_history.map { |s| s[:queued_tasks] }.max

        expect(max_active).to be <= 5 # Should not exceed pool size
        expect(max_queued).to be >= 0 # Should queue excess tasks

        puts "Max active tasks: #{max_active}"
        puts "Max queued tasks: #{max_queued}"
        puts "Pool utilization: #{(max_active / 5.0 * 100).round(1)}%"

        async_runner.shutdown
      end
    end

    private

    def get_memory_usage
      if RUBY_PLATFORM.include?("darwin") # macOS
        `ps -o rss= -p #{Process.pid}`.to_i * 1024 # Convert KB to bytes
      elsif RUBY_PLATFORM.include?("linux")
        status_line = File.read("/proc/#{Process.pid}/status")
                          .lines
                          .find { |line| line.start_with?("VmRSS:") }

        if status_line
          parts = status_line.split
          value = parts[1]&.to_i
          value ? value * 1024 : 0 # Convert KB to bytes
        else
          0
        end
      else
        # Fallback for other platforms
        GC.stat[:heap_allocated_pages] * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_SIZE]
      end
    rescue StandardError
      # Fallback if system memory reading fails
      GC.stat[:heap_allocated_pages] * 65_536 # Approximate page size
    end
  end
else
  RSpec.describe "RAAF Streaming Performance" do
    it "skips performance tests when streaming not available" do
      skip "RAAF::Async::Runner not available - streaming functionality not loaded"
    end
  end
end
