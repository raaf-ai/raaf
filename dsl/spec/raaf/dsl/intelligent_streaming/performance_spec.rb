# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require "raaf/dsl/intelligent_streaming/config"
require "raaf/dsl/intelligent_streaming/executor"
require "raaf/dsl/core/context_variables"

RSpec.describe "IntelligentStreaming Performance" do
  let(:base_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "PerformanceTestAgent"
      model "gpt-4o"

      def self.name
        "PerformanceTestAgent"
      end

      def call
        # Simulate some processing
        context[:items].map { |item| item.merge(processed: true) } if context[:items]
        context
      end
    end
  end

  let(:context_class) { RAAF::DSL::Core::ContextVariables }

  describe "streaming overhead" do
    context "overhead measurement" do
      it "keeps overhead under 5ms per stream" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 100
            over :items
          end
        end

        items = (1..1000).map { |i| { id: i, data: "item#{i}" } }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        # Measure execution time
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
        executor.execute(context)
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)

        total_time_ms = end_time - start_time
        stream_count = (items.size.to_f / 100).ceil
        overhead_per_stream = total_time_ms / stream_count

        # Should be well under 5ms per stream for overhead
        expect(overhead_per_stream).to be < 5
      end

      it "measures pure streaming overhead vs direct processing" do
        items = (1..100).map { |i| { id: i, data: "item#{i}" } }

        # Direct processing without streaming
        direct_agent = base_agent_class.new
        direct_context = context_class.new(items: items)

        direct_time = Benchmark.realtime do
          direct_agent.call
        end

        # Processing with streaming
        streaming_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items
          end
        end

        streaming_agent = streaming_agent_class.new
        streaming_context = context_class.new(items: items)
        config = streaming_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(streaming_agent, config)

        streaming_time = Benchmark.realtime do
          executor.execute(streaming_context)
        end

        overhead = (streaming_time - direct_time) * 1000 # Convert to ms
        stream_count = (items.size.to_f / 10).ceil

        # Overhead should be minimal per stream
        expect(overhead / stream_count).to be < 5
      end
    end

    context "scalability" do
      it "scales linearly with number of streams" do
        measurements = []

        [10, 50, 100, 200].each do |num_streams|
          agent_class = Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size 10
              over :items
            end
          end

          items = (1..(num_streams * 10)).map { |i| { id: i } }
          context = context_class.new(items: items)
          agent = agent_class.new
          config = agent_class._intelligent_streaming_config
          executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

          time = Benchmark.realtime { executor.execute(context) }
          measurements << { streams: num_streams, time: time }
        end

        # Calculate correlation coefficient to verify linear relationship
        if measurements.size >= 3
          # Simple linear regression check
          x_values = measurements.map { |m| m[:streams].to_f }
          y_values = measurements.map { |m| m[:time] }

          mean_x = x_values.sum / x_values.size
          mean_y = y_values.sum / y_values.size

          numerator = x_values.zip(y_values).sum { |x, y| (x - mean_x) * (y - mean_y) }
          denominator_x = Math.sqrt(x_values.sum { |x| (x - mean_x) ** 2 })
          denominator_y = Math.sqrt(y_values.sum { |y| (y - mean_y) ** 2 })

          correlation = numerator / (denominator_x * denominator_y)

          # Should have strong linear correlation (> 0.95)
          expect(correlation).to be > 0.95
        end
      end
    end
  end

  describe "memory usage" do
    context "memory proportionality" do
      it "keeps memory proportional to stream size, not total size" do
        memory_samples = {}

        [100, 500, 1000].each do |stream_size|
          agent_class = Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size stream_size
              over :items
            end
          end

          # Large dataset
          items = (1..10_000).map { |i| { id: i, data: "x" * 100 } }
          context = context_class.new(items: items)
          agent = agent_class.new
          config = agent_class._intelligent_streaming_config
          executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

          GC.start
          before_memory = GC.stat[:heap_live_slots]

          executor.execute(context)

          GC.start
          after_memory = GC.stat[:heap_live_slots]

          memory_samples[stream_size] = after_memory - before_memory
        end

        # Memory usage should scale with stream size, not total data
        # Larger stream sizes should use proportionally more memory
        if memory_samples[100] > 0 && memory_samples[1000] > 0
          ratio = memory_samples[1000].to_f / memory_samples[100]
          # Should be roughly 10x (1000/100), allowing for some variance
          expect(ratio).to be_between(5, 15)
        end
      end
    end

    context "memory cleanup" do
      it "does not accumulate memory across streams" do
        memory_checkpoints = []

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 100
            over :items

            on_stream_complete do |stream_num, total, results|
              GC.start
              memory_checkpoints << GC.stat[:heap_live_slots]
            end
          end
        end

        items = (1..1000).map { |i| { id: i, data: "x" * 1000 } }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        GC.start
        executor.execute(context)

        if memory_checkpoints.size > 3
          # Memory should not grow continuously
          first_third = memory_checkpoints[0..2].sum / 3.0
          last_third = memory_checkpoints[-3..-1].sum / 3.0

          growth_ratio = last_third / first_third
          # Should not grow more than 20%
          expect(growth_ratio).to be < 1.2
        end
      end
    end
  end

  describe "batch size optimization" do
    def measure_throughput(stream_size, total_items = 1000)
      agent_class = Class.new(base_agent_class) do
        intelligent_streaming do
          stream_size stream_size
          over :items
        end
      end

      items = (1..total_items).map { |i| { id: i, value: rand(100) } }
      context = context_class.new(items: items)
      agent = agent_class.new
      config = agent_class._intelligent_streaming_config
      executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

      time = Benchmark.realtime { executor.execute(context) }
      items_per_second = total_items / time

      { stream_size: stream_size, throughput: items_per_second, time: time }
    end

    context "small batches" do
      it "performs well with small batches (10 items)" do
        result = measure_throughput(10)

        # Should process at least 1000 items/second with small batches
        expect(result[:throughput]).to be > 1000
      end
    end

    context "medium batches" do
      it "performs well with medium batches (100 items)" do
        result = measure_throughput(100)

        # Should process at least 5000 items/second with medium batches
        expect(result[:throughput]).to be > 5000
      end
    end

    context "large batches" do
      it "performs well with large batches (1000 items)" do
        result = measure_throughput(1000, 10_000)

        # Should process at least 10000 items/second with large batches
        expect(result[:throughput]).to be > 10_000
      end
    end

    context "batch size comparison" do
      it "shows performance characteristics across batch sizes" do
        results = [10, 50, 100, 500, 1000].map do |size|
          measure_throughput(size, 5000)
        end

        # Larger batches should generally have higher throughput
        sorted_by_size = results.sort_by { |r| r[:stream_size] }
        sorted_by_throughput = results.sort_by { |r| r[:throughput] }

        # The order should be roughly the same (larger batches = higher throughput)
        size_ranks = sorted_by_size.map { |r| r[:stream_size] }
        throughput_ranks = sorted_by_throughput.map { |r| r[:stream_size] }

        # At least 60% of the order should match
        matches = size_ranks.zip(throughput_ranks).count { |a, b| a == b }
        expect(matches.to_f / size_ranks.size).to be > 0.6
      end
    end
  end

  describe "hook execution performance" do
    context "hook overhead" do
      it "keeps hook execution overhead minimal" do
        hook_times = []

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 100
            over :items

            on_stream_start do |stream_num, total, context|
              # Minimal hook logic
              context[:stream_started] = stream_num
            end

            on_stream_complete do |stream_num, total, results|
              # Minimal hook logic
              results[:stream_completed] = stream_num
            end
          end
        end

        items = (1..1000).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        # Measure with hooks
        time_with_hooks = Benchmark.realtime { executor.execute(context) }

        # Compare with no hooks
        no_hook_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 100
            over :items
          end
        end

        no_hook_agent = no_hook_agent_class.new
        no_hook_config = no_hook_agent_class._intelligent_streaming_config
        no_hook_executor = RAAF::DSL::IntelligentStreaming::Executor.new(no_hook_agent, no_hook_config)

        time_without_hooks = Benchmark.realtime { no_hook_executor.execute(context_class.new(items: items)) }

        hook_overhead = (time_with_hooks - time_without_hooks) * 1000 # ms
        stream_count = (items.size.to_f / 100).ceil

        # Hook overhead should be < 0.5ms per stream
        expect(hook_overhead / stream_count).to be < 0.5
      end
    end
  end

  describe "state management performance" do
    context "skip_if performance" do
      it "efficiently skips records" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 100
            over :items

            skip_if do |record, context|
              record[:id] % 2 == 0 # Skip even IDs
            end
          end
        end

        items = (1..1000).map { |i| { id: i, data: "item#{i}" } }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        time = Benchmark.realtime { executor.execute(context) }

        # Should be fast even with skip logic
        expect(time).to be < 0.1 # 100ms for 1000 items with skipping
      end
    end

    context "load_existing performance" do
      it "efficiently loads cached results" do
        cache = {}
        500.times { |i| cache[i * 2] = { id: i * 2, cached: true } }

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 100
            over :items

            load_existing do |record, context|
              cache[record[:id]]
            end
          end
        end

        items = (1..1000).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        time = Benchmark.realtime { executor.execute(context) }

        # Should be fast with cache lookups
        expect(time).to be < 0.1 # 100ms for 1000 items with cache
      end
    end
  end
end