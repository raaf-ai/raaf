# frozen_string_literal: true

require "spec_helper"
require "memory_profiler"
require "benchmark/memory"

RSpec.describe "Memory Profiling", :performance do
  let(:mock_provider) { create_mock_provider }

  describe "Memory allocation patterns" do
    it "profiles agent creation memory usage" do
      report = MemoryProfiler.report do
        100.times do |i|
          create_test_agent(
            name: "ProfileAgent#{i}",
            instructions: "Memory profiling test agent number #{i}"
          )
        end
      end

      # Agent creation should be memory efficient
      expect(report.total_allocated).to be < 100_000  # bytes
      expect(report.total_retained).to be < 10_000    # bytes retained

      # Should not create excessive objects per agent
      objects_per_agent = report.total_allocated / 100.0
      expect(objects_per_agent).to be < 50
    end

    it "profiles runner execution memory patterns" do
      agent = create_test_agent(name: "RunnerProfileAgent")
      mock_provider.add_response("Profiling response")
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      report = MemoryProfiler.report do
        100.times do |i|
          runner.run("Memory profile test #{i}")
        end
      end

      # Execution should have predictable memory usage
      memory_per_run = report.total_allocated / 100.0
      expect(memory_per_run).to be < 5_000 # Less than 5KB per run

      # Should not retain significant memory between runs
      retained_per_run = report.total_retained / 100.0
      expect(retained_per_run).to be < 500 # Less than 500 bytes retained
    end

    it "identifies memory hotspots in tool execution" do
      tools = 10.times.map do |i|
        RAAF::FunctionTool.new(
          proc { |data:|
            # Create some temporary objects
            result = []
            100.times { |j| result << "Tool #{i} item #{j}: #{data}" }
            result.join(", ")
          },
          name: "memory_tool_#{i}"
        )
      end

      agent = create_test_agent(name: "MemoryToolAgent")
      tools.each { |tool| agent.add_tool(tool) }

      mock_provider.add_response(
        "Using memory tool",
        tool_calls: [{
          function: {
            name: "memory_tool_5",
            arguments: '{"data": "profile test"}'
          }
        }]
      )
      mock_provider.add_response("Tool complete")

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      report = MemoryProfiler.report do
        50.times do |i|
          runner.run("Execute memory tool #{i}")
        end
      end

      # Analyze memory hotspots
      string_allocations = report.strings_allocated.size
      report.total_allocated

      # Tool execution creates temporary objects but should clean up
      expect(report.total_retained).to be < report.total_allocated * 0.1

      # Most allocations should be strings (from tool output)
      expect(string_allocations).to be_positive
    end
  end

  describe "Memory leak detection" do
    it "profiles memory usage in complex multi-agent scenarios" do
      # Create complex agent network
      agents = 10.times.map do |i|
        agent = create_test_agent(name: "ComplexAgent#{i}")

        # Add tools to each agent
        3.times do |j|
          tool = RAAF::FunctionTool.new(
            proc { |input:| "Agent #{i} tool #{j}: #{input}" },
            name: "agent#{i}_tool#{j}"
          )
          agent.add_tool(tool)
        end

        agent
      end

      # Set up handoffs
      agents.each_cons(2) { |a, b| a.add_handoff(b) }

      # Prepare complex interaction responses
      100.times do |i|
        # Sometimes use tools, sometimes handoff
        if (i % 3).zero?
          tool_calls = [{
            function: {
              name: "agent#{i % 10}_tool#{i % 3}",
              arguments: JSON.generate({ input: "Complex test #{i}" })
            }
          }]
          mock_provider.add_response("Using tool", tool_calls: tool_calls)
        elsif (i % 5).zero?
          handoff_calls = [{
            function: {
              name: "transfer_to_complexagent#{(i + 1) % 10}",
              arguments: "{}"
            }
          }]
          mock_provider.add_response("Handing off", tool_calls: handoff_calls)
        else
          mock_provider.add_response("Regular response #{i}")
        end
      end

      report = MemoryProfiler.report do
        runner = RAAF::Runner.new(agent: agents.first, provider: mock_provider)

        20.times do |i|
          runner.run("Complex scenario #{i}")
        end
      end

      # Complex scenarios should still be memory efficient
      memory_per_scenario = report.total_allocated / 20.0
      expect(memory_per_scenario).to be < 50_000 # Less than 50KB per scenario

      # Should not retain significant memory
      expect(report.total_retained).to be < report.total_allocated * 0.2
    end
  end

  describe "Garbage collection impact" do
    it "measures GC pressure during high throughput" do
      agent = create_test_agent(name: "GCTestAgent")
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      # Prepare responses
      1000.times { mock_provider.add_response("GC test response") }

      # Track GC stats
      initial_gc_count = GC.count
      gc_time_before = GC.stat[:time]

      # Run high-throughput operations
      1000.times do |i|
        runner.run("GC test #{i}")
      end

      final_gc_count = GC.count
      gc_time_after = GC.stat[:time]

      # Analyze GC impact
      gc_invocations = final_gc_count - initial_gc_count
      gc_time_spent = gc_time_after - gc_time_before

      # Should not trigger excessive GC
      expect(gc_invocations).to be < 50 # Less than 50 GC cycles

      # GC time should be reasonable
      gc_time_per_operation = gc_time_spent.to_f / 1000
      expect(gc_time_per_operation).to be < 1000 # Less than 1ms GC time per operation
    end
  end

  describe "Memory benchmarking" do
    it "benchmarks memory usage across different operation types" do
      include Benchmark::Memory

      agent = create_test_agent(name: "BenchmarkAgent")

      # Simple operation
      simple_benchmark = MemoryProfiler.report do
        mock_provider.add_response("Simple")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        runner.run("Simple test")
      end

      # Tool operation
      tool = RAAF::FunctionTool.new(
        proc { |x:| "Tool result: #{x}" },
        name: "bench_tool"
      )
      agent.add_tool(tool)

      tool_benchmark = MemoryProfiler.report do
        mock_provider.add_response(
          "Using tool",
          tool_calls: [{ function: { name: "bench_tool", arguments: '{"x": "test"}' } }]
        )
        mock_provider.add_response("Tool done")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        runner.run("Tool test")
      end

      # Compare memory usage
      expect(tool_benchmark.total_allocated_memsize).to be > simple_benchmark.total_allocated_memsize
      expect(tool_benchmark.total_allocated_memsize).to be < simple_benchmark.total_allocated_memsize * 3 # Not more than 3x

      # Both should have minimal retained memory
      expect(simple_benchmark.total_retained_memsize).to be < 10_000   # Less than 10KB retained
      expect(tool_benchmark.total_retained_memsize).to be < 20_000     # Less than 20KB retained
    end

    it "benchmarks memory efficiency of different configurations" do
      include Benchmark::Memory

      base_agent = create_test_agent(name: "BaseAgent")
      mock_provider.add_response("Base response")

      # Minimal configuration
      minimal_memory = MemoryProfiler.report do
        runner = RAAF::Runner.new(agent: base_agent, provider: mock_provider)
        runner.run("Minimal test")
      end

      # Complex configuration
      complex_config = RAAF::RunConfig.new(
        max_turns: 50,
        max_tokens: 2000,
        metadata: {
          app: "benchmark",
          version: "1.0",
          features: Array.new(100) { |i| "feature_#{i}" }
        }
      )

      mock_provider.add_response("Complex response")

      complex_memory = MemoryProfiler.report do
        runner = RAAF::Runner.new(
          agent: base_agent,
          provider: mock_provider
        )
        runner.run("Complex test", config: complex_config)
      end

      # Complex config should not dramatically increase memory usage
      memory_overhead = complex_memory.total_allocated_memsize - minimal_memory.total_allocated_memsize
      expect(memory_overhead).to be < 50_000 # Less than 50KB overhead

      # Retained memory should be similar
      retained_overhead = complex_memory.total_retained_memsize - minimal_memory.total_retained_memsize
      expect(retained_overhead).to be < 10_000 # Less than 10KB retained overhead
    end
  end
end
