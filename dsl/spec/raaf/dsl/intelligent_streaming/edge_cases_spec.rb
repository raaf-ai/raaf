# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/intelligent_streaming/config"
require "raaf/dsl/intelligent_streaming/scope"
require "raaf/dsl/intelligent_streaming/manager"
require "raaf/dsl/intelligent_streaming/executor"
require "raaf/dsl/core/context_variables"

RSpec.describe "IntelligentStreaming Edge Cases" do
  let(:base_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "TestAgent"
      model "gpt-4o"

      def self.name
        "TestAgent"
      end

      def call
        context
      end
    end
  end

  let(:streaming_agent_class) do
    Class.new(base_agent_class) do
      intelligent_streaming do
        stream_size 10
        over :items
      end
    end
  end

  let(:context_class) { RAAF::DSL::Core::ContextVariables }

  describe "empty arrays" do
    context "with 0 items" do
      it "handles empty arrays gracefully" do
        context = context_class.new(items: [])
        agent = streaming_agent_class.new
        config = streaming_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        expect(result).to be_a(context_class)
        expect(result[:items]).to eq([])
        expect(result[:success]).to be true
      end

      it "does not call any stream hooks for empty arrays" do
        hook_calls = []

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            on_stream_start do |stream_num, total, context|
              hook_calls << { type: :start, stream: stream_num, total: total }
            end

            on_stream_complete do |stream_num, total, results|
              hook_calls << { type: :complete, stream: stream_num, total: total }
            end
          end
        end

        context = context_class.new(items: [])
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        executor.execute(context)

        expect(hook_calls).to be_empty
      end
    end
  end

  describe "single item" do
    context "with 1 item" do
      it "processes single item correctly" do
        context = context_class.new(items: ["item1"])
        agent = streaming_agent_class.new
        config = streaming_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        expect(result).to be_a(context_class)
        expect(result[:items]).to eq(["item1"])
        expect(result[:success]).to be true
      end

      it "creates exactly one stream for single item" do
        stream_count = 0

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            on_stream_start do |stream_num, total, context|
              stream_count += 1
            end
          end
        end

        context = context_class.new(items: ["item1"])
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        executor.execute(context)

        expect(stream_count).to eq(1)
      end
    end
  end

  describe "exact stream size match" do
    context "with items equal to stream_size" do
      it "creates one stream for exact size" do
        stream_info = []

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 100
            over :items

            on_stream_start do |stream_num, total, context|
              stream_info << { stream: stream_num, total: total, size: context[:items].size }
            end
          end
        end

        items = (1..100).map { |i| "item#{i}" }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        executor.execute(context)

        expect(stream_info.size).to eq(1)
        expect(stream_info[0][:stream]).to eq(1)
        expect(stream_info[0][:total]).to eq(1)
        expect(stream_info[0][:size]).to eq(100)
      end
    end
  end

  describe "boundary conditions" do
    context "with one less than stream size" do
      it "creates one stream for size-1 items" do
        stream_count = 0

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 100
            over :items

            on_stream_start do |stream_num, total, context|
              stream_count += 1
            end
          end
        end

        items = (1..99).map { |i| "item#{i}" }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        executor.execute(context)

        expect(stream_count).to eq(1)
      end
    end

    context "with one more than stream size" do
      it "creates two streams for size+1 items" do
        stream_info = []

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 100
            over :items

            on_stream_start do |stream_num, total, context|
              stream_info << { stream: stream_num, total: total, size: context[:items].size }
            end
          end
        end

        items = (1..101).map { |i| "item#{i}" }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        executor.execute(context)

        expect(stream_info.size).to eq(2)
        expect(stream_info[0][:size]).to eq(100)
        expect(stream_info[1][:size]).to eq(1)
      end
    end

    context "with exactly double stream size" do
      it "creates exactly two full streams" do
        stream_info = []

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 50
            over :items

            on_stream_start do |stream_num, total, context|
              stream_info << { stream: stream_num, size: context[:items].size }
            end
          end
        end

        items = (1..100).map { |i| "item#{i}" }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        executor.execute(context)

        expect(stream_info.size).to eq(2)
        expect(stream_info.all? { |s| s[:size] == 50 }).to be true
      end
    end
  end

  describe "very large arrays" do
    context "with 10000+ items" do
      it "processes large datasets correctly" do
        items = (1..10_000).map { |i| { id: i, value: "item#{i}" } }

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 1000
            over :items
          end
        end

        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        expect(result[:items].size).to eq(10_000)
        expect(result[:success]).to be true
      end

      it "creates correct number of streams for large datasets" do
        stream_count = 0

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 1000
            over :items

            on_stream_start do |stream_num, total, context|
              stream_count += 1
            end
          end
        end

        items = (1..10_000).map { |i| "item#{i}" }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        executor.execute(context)

        expect(stream_count).to eq(10) # 10,000 / 1,000 = 10 streams
      end

      it "does not accumulate excessive memory across streams" do
        memory_samples = []

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 1000
            over :items

            on_stream_complete do |stream_num, total, results|
              # Sample memory usage
              memory_samples << GC.stat[:heap_live_slots]
            end
          end
        end

        items = (1..10_000).map { |i| { id: i, data: "x" * 100 } }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        GC.start # Clean baseline
        executor.execute(context)

        # Memory should not grow excessively between streams
        if memory_samples.size > 2
          memory_growth = memory_samples.last - memory_samples.first
          avg_memory = memory_samples.sum / memory_samples.size

          # Memory growth should be less than 20% of average
          expect(memory_growth).to be < (avg_memory * 0.2)
        end
      end
    end
  end

  describe "nil or missing fields" do
    context "with nil array field" do
      it "raises clear error for nil field" do
        context = context_class.new(items: nil, other_data: "present")
        agent = streaming_agent_class.new
        config = streaming_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        expect {
          executor.execute(context)
        }.to raise_error(ArgumentError, /Field 'items' is nil or not an array/)
      end
    end

    context "with missing array field" do
      it "raises clear error for missing field" do
        context = context_class.new(other_data: "present") # No 'items' field
        agent = streaming_agent_class.new
        config = streaming_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        expect {
          executor.execute(context)
        }.to raise_error(ArgumentError, /Field 'items' is nil or not an array/)
      end
    end

    context "with non-array field" do
      it "raises clear error for string field" do
        context = context_class.new(items: "not an array")
        agent = streaming_agent_class.new
        config = streaming_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        expect {
          executor.execute(context)
        }.to raise_error(ArgumentError, /Field 'items' is nil or not an array/)
      end

      it "raises clear error for hash field" do
        context = context_class.new(items: { key: "value" })
        agent = streaming_agent_class.new
        config = streaming_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        expect {
          executor.execute(context)
        }.to raise_error(ArgumentError, /Field 'items' is nil or not an array/)
      end

      it "raises clear error for numeric field" do
        context = context_class.new(items: 42)
        agent = streaming_agent_class.new
        config = streaming_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        expect {
          executor.execute(context)
        }.to raise_error(ArgumentError, /Field 'items' is nil or not an array/)
      end
    end
  end

  describe "unusual array contents" do
    context "with mixed types in array" do
      it "handles arrays with mixed types" do
        mixed_items = [
          "string",
          42,
          { key: "value" },
          ["nested", "array"],
          nil,
          true,
          3.14
        ]

        context = context_class.new(items: mixed_items)
        agent = streaming_agent_class.new
        config = streaming_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        expect(result[:items]).to eq(mixed_items)
        expect(result[:success]).to be true
      end
    end

    context "with deeply nested structures" do
      it "handles arrays with deeply nested objects" do
        nested_items = [
          {
            level1: {
              level2: {
                level3: {
                  level4: {
                    value: "deep"
                  }
                }
              }
            }
          }
        ] * 5

        context = context_class.new(items: nested_items)
        agent = streaming_agent_class.new
        config = streaming_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        expect(result[:items].size).to eq(5)
        expect(result[:items].first.dig(:level1, :level2, :level3, :level4, :value)).to eq("deep")
      end
    end
  end

  describe "stream size edge cases" do
    context "with stream_size of 1" do
      it "creates one stream per item" do
        stream_count = 0

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 1
            over :items

            on_stream_start do |stream_num, total, context|
              stream_count += 1
            end
          end
        end

        items = ["a", "b", "c", "d", "e"]
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        executor.execute(context)

        expect(stream_count).to eq(5)
      end
    end

    context "with very large stream_size" do
      it "creates single stream if stream_size exceeds array size" do
        stream_count = 0

        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 1_000_000
            over :items

            on_stream_start do |stream_num, total, context|
              stream_count += 1
            end
          end
        end

        items = (1..100).map { |i| "item#{i}" }
        context = context_class.new(items: items)
        agent = agent_class.new
        config = agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        executor.execute(context)

        expect(stream_count).to eq(1)
      end
    end
  end
end