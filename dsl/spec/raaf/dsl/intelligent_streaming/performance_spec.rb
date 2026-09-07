# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/intelligent_streaming/config"
require "raaf/dsl/intelligent_streaming/scope"
require "raaf/dsl/intelligent_streaming/executor"
require "raaf/dsl/core/context_variables"

# Streaming exists to keep work proportional to the stream, not to the whole
# array. These examples pin down that proportionality rather than absolute
# timings, which vary too much between machines to assert on.
RSpec.describe "IntelligentStreaming Performance" do
  let(:context_class) { RAAF::DSL::ContextVariables }

  let(:processing_agent) do
    Class.new do
      def self.name
        "PerformanceTestAgent"
      end

      def run(context: {})
        context.merge(processed: true)
      end
    end
  end

  def executor_for(config, context)
    scope = RAAF::DSL::IntelligentStreaming::Scope.new(
      trigger_agent: processing_agent,
      scope_agents: [processing_agent],
      stream_size: config.stream_size,
      array_field: config.array_field
    )

    RAAF::DSL::IntelligentStreaming::Executor.new(scope: scope, context: context, config: config)
  end

  def config_for(stream_size: 100, over: :items, incremental: false, &block)
    config = RAAF::DSL::IntelligentStreaming::Config.new(
      stream_size: stream_size,
      over: over,
      incremental: incremental
    )
    config.instance_eval(&block) if block
    config
  end

  def items_for(count)
    (1..count).map { |i| { id: i, data: "item#{i}" } }
  end

  describe "stream splitting" do
    it "splits the array into ceil(size / stream_size) streams" do
      executor = executor_for(config_for(stream_size: 10), context_class.new(items: items_for(100)))
      executor.execute([])

      expect(executor.execution_stats[:total_streams]).to eq(10)
    end

    it "puts the remainder in a final short stream" do
      sizes = []
      config = config_for(stream_size: 10) do
        on_stream_start { |_num, _total, stream_items| sizes << stream_items.size }
      end

      executor_for(config, context_class.new(items: items_for(105))).execute([])

      expect(sizes.last).to eq(5)
      expect(sizes.sum).to eq(105)
    end

    it "scales the stream count linearly with the array size" do
      counts = [50, 100, 200].map do |size|
        executor = executor_for(config_for(stream_size: 10), context_class.new(items: items_for(size)))
        executor.execute([])
        executor.execution_stats[:total_streams]
      end

      expect(counts).to eq([5, 10, 20])
    end
  end

  describe "memory proportionality" do
    it "hands each hook only one stream's worth of items" do
      seen = []
      config = config_for(stream_size: 50) do
        on_stream_start { |_num, _total, stream_items| seen << stream_items.size }
      end

      executor_for(config, context_class.new(items: items_for(500))).execute([])

      expect(seen.uniq).to eq([50])
    end

    it "accumulates one entry per stream, not per item" do
      executor = executor_for(config_for(stream_size: 10), context_class.new(items: items_for(100)))
      executor.execute([])

      expect(executor.accumulated_results.size).to eq(10)
    end
  end

  describe "batch sizes" do
    it "processes every item whatever the stream size" do
      [10, 50, 100].each do |stream_size|
        executor = executor_for(config_for(stream_size: stream_size), context_class.new(items: items_for(100)))

        expect(executor.execute([processing_agent.new]).size).to eq(100)
      end
    end

    it "does fewer, larger streams as the stream size grows" do
      stream_counts = [1, 10, 100].map do |stream_size|
        executor = executor_for(config_for(stream_size: stream_size), context_class.new(items: items_for(100)))
        executor.execute([])
        executor.execution_stats[:total_streams]
      end

      expect(stream_counts).to eq([100, 10, 1])
    end
  end

  describe "hooks" do
    it "calls each progress hook once per stream" do
      starts = 0
      completes = 0
      config = config_for(stream_size: 10, incremental: true) do
        on_stream_start { |_num, _total, _items| starts += 1 }
        on_stream_complete { |_num, _total, _data, _results| completes += 1 }
      end

      executor_for(config, context_class.new(items: items_for(100))).execute([])

      expect(starts).to eq(10)
      expect(completes).to eq(10)
    end

    it "calls on_stream_complete once for the whole run in accumulating mode" do
      completes = 0
      config = config_for(stream_size: 10) do
        on_stream_complete { |_all_results| completes += 1 }
      end

      executor_for(config, context_class.new(items: items_for(100))).execute([])

      expect(completes).to eq(1)
    end

    it "calls a hook once per stream and no more" do
      calls = 0
      config = config_for(stream_size: 10) do
        on_stream_start { |_num, _total, _items| calls += 1 }
      end

      executor_for(config, context_class.new(items: items_for(100))).execute([])

      expect(calls).to eq(10)
    end
  end

  describe "state management" do
    it "skips records the skip_if block rejects" do
      config = config_for(stream_size: 10) do
        skip_if { |record, _context| record[:id].even? }
      end

      executor = executor_for(config, context_class.new(items: items_for(100)))
      executor.execute([processing_agent.new])

      expect(executor.execution_stats[:skipped_items]).to eq(50)
      expect(executor.execution_stats[:processed_items]).to eq(50)
    end

    it "substitutes cached results for skipped records" do
      config = config_for(stream_size: 10) do
        skip_if { |record, _context| record[:id].even? }
        load_existing { |record, _context| { id: record[:id], cached: true } }
      end

      executor = executor_for(config, context_class.new(items: items_for(100)))
      results = executor.execute([processing_agent.new])

      cached = results.select { |result| result[:cached] }
      expect(cached.size).to eq(50)
    end

    it "hands the persist block each stream's results once" do
      persisted = []
      config = config_for(stream_size: 50) do
        persist { |stream_results, _context| persisted << stream_results.size }
      end

      executor_for(config, context_class.new(items: items_for(100))).execute([processing_agent.new])

      expect(persisted).to eq([50, 50])
    end
  end
end
