# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/intelligent_streaming/config"
require "raaf/dsl/intelligent_streaming/scope"
require "raaf/dsl/intelligent_streaming/manager"
require "raaf/dsl/intelligent_streaming/executor"
require "raaf/dsl/core/context_variables"

RSpec.describe "IntelligentStreaming Edge Cases" do
  let(:context_class) { RAAF::DSL::ContextVariables }

  # A minimal agent for the chain: it stamps the record it was handed so the
  # executor's per-record results are recognisable.
  let(:processing_agent) do
    Class.new do
      def self.name
        "ProcessingAgent"
      end

      def run(context: {})
        context.merge(processed: true)
      end
    end
  end

  let(:agent_chain) { [processing_agent.new] }

  # Builds an executor for a config, wiring up the scope the executor needs.
  def executor_for(config, context)
    scope = RAAF::DSL::IntelligentStreaming::Scope.new(
      trigger_agent: processing_agent,
      scope_agents: [processing_agent],
      stream_size: config.stream_size,
      array_field: config.array_field
    )

    RAAF::DSL::IntelligentStreaming::Executor.new(scope: scope, context: context, config: config)
  end

  def config_for(stream_size: 10, over: :items, incremental: false, &block)
    config = RAAF::DSL::IntelligentStreaming::Config.new(
      stream_size: stream_size,
      over: over,
      incremental: incremental
    )
    config.instance_eval(&block) if block
    config
  end

  describe "empty arrays" do
    context "with 0 items" do
      it "returns no results" do
        executor = executor_for(config_for, context_class.new(items: []))

        expect(executor.execute(agent_chain)).to eq([])
      end

      it "records that there was nothing to process" do
        executor = executor_for(config_for, context_class.new(items: []))
        executor.execute(agent_chain)

        expect(executor.execution_stats[:total_items]).to eq(0)
        expect(executor.execution_stats[:total_streams]).to eq(0)
      end

      it "does not call any stream hooks for empty arrays" do
        hook_calls = []
        config = config_for do
          on_stream_start { |num, total, _items| hook_calls << { type: :start, stream: num, total: total } }
          on_stream_complete { |_all_results| hook_calls << { type: :complete } }
        end

        executor_for(config, context_class.new(items: [])).execute(agent_chain)

        expect(hook_calls).to be_empty
      end
    end
  end

  describe "single item" do
    context "with 1 item" do
      it "processes the item through the agent chain" do
        executor = executor_for(config_for, context_class.new(items: ["item1"]))

        results = executor.execute(agent_chain)

        expect(results.size).to eq(1)
        expect(results.first[:current_record]).to eq("item1")
        expect(results.first[:processed]).to be true
      end

      it "creates exactly one stream for a single item" do
        streams = []
        config = config_for { on_stream_start { |num, total, _items| streams << [num, total] } }

        executor_for(config, context_class.new(items: ["item1"])).execute(agent_chain)

        expect(streams).to eq([[1, 1]])
      end
    end
  end

  describe "stream boundaries" do
    def stream_sizes_for(item_count, stream_size)
      sizes = []
      config = config_for(stream_size: stream_size) do
        on_stream_start { |_num, _total, items| sizes << items.size }
      end

      items = (1..item_count).map { |i| "item#{i}" }
      executor_for(config, context_class.new(items: items)).execute([])

      sizes
    end

    it "creates one stream when the item count equals the stream size" do
      expect(stream_sizes_for(10, 10)).to eq([10])
    end

    it "creates one stream when the item count is one below the stream size" do
      expect(stream_sizes_for(9, 10)).to eq([9])
    end

    it "creates two streams when the item count is one above the stream size" do
      expect(stream_sizes_for(11, 10)).to eq([10, 1])
    end

    it "creates two full streams at exactly double the stream size" do
      expect(stream_sizes_for(20, 10)).to eq([10, 10])
    end

    it "creates one stream per item when the stream size is 1" do
      expect(stream_sizes_for(5, 1)).to eq([1, 1, 1, 1, 1])
    end

    it "creates a single stream when the stream size exceeds the array size" do
      expect(stream_sizes_for(100, 1_000_000)).to eq([100])
    end
  end

  describe "very large arrays" do
    let(:items) { (1..2_000).map { |i| "item#{i}" } }

    it "processes every item" do
      executor = executor_for(config_for(stream_size: 100), context_class.new(items: items))

      results = executor.execute(agent_chain)

      expect(results.size).to eq(2_000)
      expect(executor.execution_stats[:processed_items]).to eq(2_000)
    end

    it "creates the expected number of streams" do
      executor = executor_for(config_for(stream_size: 100), context_class.new(items: items))
      executor.execute([])

      expect(executor.execution_stats[:total_streams]).to eq(20)
      expect(executor.execution_stats[:successful_streams]).to eq(20)
    end
  end

  describe "nil or missing fields" do
    it "raises a clear error when the configured field is nil" do
      executor = executor_for(config_for, context_class.new(items: nil, other_data: "present"))

      expect { executor.execute(agent_chain) }.to raise_error(
        RAAF::DSL::IntelligentStreaming::ExecutorError,
        /No array field 'items' found in context/
      )
    end

    it "raises a clear error when the configured field is absent" do
      executor = executor_for(config_for, context_class.new(other_data: "present"))

      expect { executor.execute(agent_chain) }.to raise_error(
        RAAF::DSL::IntelligentStreaming::ExecutorError,
        /No array field 'items' found in context/
      )
    end

    it "raises a clear error when the field holds a string" do
      executor = executor_for(config_for, context_class.new(items: "not an array"))

      expect { executor.execute(agent_chain) }.to raise_error(
        RAAF::DSL::IntelligentStreaming::ExecutorError,
        /does not contain an array, got: String/
      )
    end

    it "raises a clear error when the field holds a hash" do
      executor = executor_for(config_for, context_class.new(items: { key: "value" }))

      expect { executor.execute(agent_chain) }.to raise_error(
        RAAF::DSL::IntelligentStreaming::ExecutorError,
        /does not contain an array/
      )
    end

    it "raises a clear error when the field holds a number" do
      executor = executor_for(config_for, context_class.new(items: 42))

      expect { executor.execute(agent_chain) }.to raise_error(
        RAAF::DSL::IntelligentStreaming::ExecutorError,
        /does not contain an array, got: Integer/
      )
    end
  end

  describe "auto-detecting the array field" do
    it "uses the only array in the context when no field is configured" do
      executor = executor_for(config_for(over: nil), context_class.new(records: %w[a b], note: "x"))

      expect(executor.execute(agent_chain).size).to eq(2)
    end

    it "refuses to guess between several arrays" do
      config = config_for(over: nil)
      scope = RAAF::DSL::IntelligentStreaming::Scope.new(
        trigger_agent: processing_agent,
        scope_agents: [processing_agent],
        stream_size: config.stream_size,
        array_field: nil
      )
      context = context_class.new(records: %w[a b], others: %w[c])
      executor = RAAF::DSL::IntelligentStreaming::Executor.new(scope: scope, context: context, config: config)

      expect { executor.execute(agent_chain) }.to raise_error(
        RAAF::DSL::IntelligentStreaming::ExecutorError,
        /Multiple array fields found/
      )
    end

    it "reports when there is no array to stream at all" do
      config = config_for(over: nil)
      scope = RAAF::DSL::IntelligentStreaming::Scope.new(
        trigger_agent: processing_agent,
        scope_agents: [processing_agent],
        stream_size: config.stream_size,
        array_field: nil
      )
      context = context_class.new(note: "x")
      executor = RAAF::DSL::IntelligentStreaming::Executor.new(scope: scope, context: context, config: config)

      expect { executor.execute(agent_chain) }.to raise_error(
        RAAF::DSL::IntelligentStreaming::ExecutorError,
        /No array fields found in context/
      )
    end
  end

  describe "unusual array contents" do
    it "handles arrays with mixed types" do
      mixed_items = ["string", 42, { key: "value" }, [1, 2, 3], nil, true]
      executor = executor_for(config_for, context_class.new(items: mixed_items))

      results = executor.execute(agent_chain)

      expect(results.size).to eq(mixed_items.size)
      expect(results.map { |r| r[:current_record] }).to eq(["string", 42, { "key" => "value" }, [1, 2, 3], nil, true])
    end

    it "handles arrays with deeply nested objects" do
      nested_items = [{ level1: { level2: { level3: { value: "deep" } } } }]
      executor = executor_for(config_for, context_class.new(items: nested_items))

      results = executor.execute(agent_chain)

      expect(results.first[:current_record][:level1][:level2][:level3][:value]).to eq("deep")
    end
  end
end
