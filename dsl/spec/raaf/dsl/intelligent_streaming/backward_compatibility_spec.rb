# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl/pipeline"
require "raaf/dsl/agent"
require "raaf/dsl/pipeline_dsl/chained_agent"
require "raaf/dsl/pipeline_dsl/parallel_agents"
require "raaf/dsl/pipeline_dsl/batched_agent"
require "raaf/dsl/intelligent_streaming/config"
require "raaf/dsl/intelligent_streaming/executor"
require "raaf/dsl/core/context_variables"

RSpec.describe "IntelligentStreaming Backward Compatibility" do
  let(:context_class) { RAAF::DSL::Core::ContextVariables }

  # Standard agents without intelligent streaming
  let(:standard_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "StandardAgent"
      model "gpt-4o"

      def self.name
        "StandardAgent"
      end

      def call
        context[:processed] = true
        context[:agent_name] = self.class.name
        context
      end
    end
  end

  let(:processor_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ProcessorAgent"
      model "gpt-4o"

      def self.name
        "ProcessorAgent"
      end

      def call
        context[:items] = context[:items].map { |item| item.merge(processed: true) } if context[:items]
        context[:processor_run] = true
        context
      end
    end
  end

  # Agent with in_chunks_of batching (existing feature)
  let(:chunked_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ChunkedAgent"
      model "gpt-4o"
      in_chunks_of 5

      def self.name
        "ChunkedAgent"
      end

      def call
        context[:chunk_processed] = true
        context[:chunk_size] = context[:items].size if context[:items]
        context
      end
    end
  end

  # Agent with intelligent streaming (new feature)
  let(:streaming_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "StreamingAgent"
      model "gpt-4o"

      intelligent_streaming do
        stream_size 10
        over :items
      end

      def self.name
        "StreamingAgent"
      end

      def call
        context[:stream_processed] = true
        context
      end
    end
  end

  describe "existing pipelines" do
    context "pipelines without intelligent_streaming" do
      it "works unchanged without intelligent_streaming" do
        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow standard_agent_class >> processor_agent_class

          context do
            default :items, []
          end
        end

        items = (1..20).map { |i| { id: i } }
        pipeline = pipeline_class.new(items: items)
        result = pipeline.run

        expect(result[:processed]).to be true
        expect(result[:processor_run]).to be true
        expect(result[:items].all? { |item| item[:processed] }).to be true
      end

      it "maintains performance without regression" do
        # Pipeline without intelligent streaming
        standard_pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow standard_agent_class >> processor_agent_class
        end

        items = (1..100).map { |i| { id: i } }
        standard_pipeline = standard_pipeline_class.new(items: items)

        # Measure standard pipeline performance
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
        standard_result = standard_pipeline.run
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
        standard_time = end_time - start_time

        expect(standard_result[:processed]).to be true
        expect(standard_result[:processor_run]).to be true

        # Performance should be consistent (this is a baseline test)
        expect(standard_time).to be < 100 # Should complete quickly
      end
    end

    context "with in_chunks_of agent batching" do
      it "works with in_chunks_of agent batching" do
        # Agent with in_chunks_of
        batched_agent = RAAF::DSL::PipelineDSL::BatchedAgent.new(
          chunked_agent_class.new,
          chunk_size: 5,
          input_field: :items,
          output_field: :items
        )

        items = (1..20).map { |i| { id: i } }
        context = context_class.new(items: items)

        result = batched_agent.execute(context)

        expect(result[:chunk_processed]).to be true
        # Should process in chunks of 5
        expect(result[:chunk_size]).to be <= 5
      end

      it "allows in_chunks_of and intelligent_streaming in same pipeline" do
        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow chunked_agent_class >> streaming_agent_class >> processor_agent_class

          context do
            default :items, []
          end
        end

        items = (1..30).map { |i| { id: i } }
        pipeline = pipeline_class.new(items: items)
        result = pipeline.run

        expect(result[:chunk_processed]).to be true
        expect(result[:stream_processed]).to be true
        expect(result[:processor_run]).to be true
      end
    end
  end

  describe "existing agents" do
    context "agents without streaming config" do
      it "agents without streaming config work unchanged" do
        agent = standard_agent_class.new
        context = context_class.new(data: "test")

        result = agent.call

        expect(result[:processed]).to be true
        expect(result[:agent_name]).to eq("StandardAgent")
      end

      it "handles nil intelligent_streaming_config gracefully" do
        agent = standard_agent_class.new

        expect(agent.class.respond_to?(:_intelligent_streaming_config)).to be true
        expect(agent.class._intelligent_streaming_config).to be_nil
      end
    end

    context "mixed pipelines" do
      it "works with mixed streaming and non-streaming agents" do
        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow standard_agent_class >> streaming_agent_class >> processor_agent_class

          context do
            default :items, []
          end
        end

        items = (1..50).map { |i| { id: i } }
        pipeline = pipeline_class.new(items: items)
        result = pipeline.run

        # All agents should have run
        expect(result[:processed]).to be true
        expect(result[:stream_processed]).to be true
        expect(result[:processor_run]).to be true
        expect(result[:items].size).to eq(50)
      end

      it "preserves execution order with mixed agents" do
        execution_order = []

        tracking_standard = Class.new(standard_agent_class) do
          define_method :call do
            execution_order << :standard
            super()
          end
        end

        tracking_streaming = Class.new(streaming_agent_class) do
          define_method :call do
            execution_order << :streaming
            super()
          end
        end

        tracking_processor = Class.new(processor_agent_class) do
          define_method :call do
            execution_order << :processor
            super()
          end
        end

        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow tracking_standard >> tracking_streaming >> tracking_processor
        end

        items = (1..20).map { |i| { id: i } }
        pipeline = pipeline_class.new(items: items)
        pipeline.run

        # Verify execution order
        # Standard runs once, streaming runs multiple times (once per stream), processor runs once
        expect(execution_order.first).to eq(:standard)
        expect(execution_order.last).to eq(:processor)
        expect(execution_order.count(:streaming)).to be >= 1
      end
    end
  end

  describe "existing operators" do
    context ">> operator (sequential)" do
      it ">> operator works with streaming" do
        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow standard_agent_class >> streaming_agent_class >> processor_agent_class
        end

        items = (1..30).map { |i| { id: i } }
        pipeline = pipeline_class.new(items: items)
        result = pipeline.run

        expect(result[:processed]).to be true
        expect(result[:stream_processed]).to be true
        expect(result[:processor_run]).to be true
      end
    end

    context "| operator (parallel)" do
      it "| operator works with streaming agents" do
        parallel_agent1 = Class.new(standard_agent_class) do
          define_method :call do
            context[:parallel1] = true
            context
          end
        end

        parallel_agent2 = Class.new(standard_agent_class) do
          define_method :call do
            context[:parallel2] = true
            context
          end
        end

        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow streaming_agent_class >> (parallel_agent1 | parallel_agent2) >> processor_agent_class
        end

        items = (1..20).map { |i| { id: i } }
        pipeline = pipeline_class.new(items: items)
        result = pipeline.run

        expect(result[:stream_processed]).to be true
        expect(result[:parallel1]).to be true
        expect(result[:parallel2]).to be true
        expect(result[:processor_run]).to be true
      end

      it "handles parallel streaming agents" do
        streaming_agent1 = Class.new(streaming_agent_class) do
          define_method :call do
            context[:stream1] = true
            context
          end
        end

        streaming_agent2 = Class.new(streaming_agent_class) do
          define_method :call do
            context[:stream2] = true
            context
          end
        end

        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow standard_agent_class >> (streaming_agent1 | streaming_agent2) >> processor_agent_class
        end

        items = (1..20).map { |i| { id: i } }
        pipeline = pipeline_class.new(items: items)
        result = pipeline.run

        expect(result[:processed]).to be true
        expect(result[:stream1]).to be true
        expect(result[:stream2]).to be true
        expect(result[:processor_run]).to be true
      end
    end

    context "complex operator combinations" do
      it "handles complex combinations of >> and |" do
        agent1 = Class.new(standard_agent_class) do
          define_method :call do
            context[:agent1] = true
            context
          end
        end

        agent2 = Class.new(standard_agent_class) do
          define_method :call do
            context[:agent2] = true
            context
          end
        end

        agent3 = Class.new(standard_agent_class) do
          define_method :call do
            context[:agent3] = true
            context
          end
        end

        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow agent1 >> (streaming_agent_class | agent2) >> agent3 >> processor_agent_class
        end

        items = (1..15).map { |i| { id: i } }
        pipeline = pipeline_class.new(items: items)
        result = pipeline.run

        expect(result[:agent1]).to be true
        expect(result[:stream_processed]).to be true
        expect(result[:agent2]).to be true
        expect(result[:agent3]).to be true
        expect(result[:processor_run]).to be true
      end
    end
  end

  describe "configuration compatibility" do
    context "agent configuration methods" do
      it "doesn't interfere with existing agent configuration" do
        configured_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "ConfiguredAgent"
          model "gpt-4o-mini"
          temperature 0.7
          max_tokens 1000

          # Also has intelligent streaming
          intelligent_streaming do
            stream_size 25
            over :records
          end

          def call
            context[:configured] = true
            context
          end
        end

        agent = configured_agent.new
        expect(agent.class.agent_name).to eq("ConfiguredAgent")
        expect(agent.class.model).to eq("gpt-4o-mini")
        expect(agent.class._intelligent_streaming_config).not_to be_nil
        expect(agent.class._intelligent_streaming_config.stream_size).to eq(25)
      end
    end

    context "context handling" do
      it "preserves context through mixed pipeline" do
        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow standard_agent_class >> streaming_agent_class >> processor_agent_class

          context do
            required :items
            optional :metadata, {}
          end
        end

        items = (1..30).map { |i| { id: i } }
        metadata = { source: "test", version: 1 }

        pipeline = pipeline_class.new(items: items, metadata: metadata)
        result = pipeline.run

        # Context should be preserved
        expect(result[:metadata]).to eq(metadata)
        expect(result[:items].size).to eq(30)
        expect(result[:processed]).to be true
      end
    end
  end

  describe "error handling compatibility" do
    context "with existing error handling" do
      it "maintains error handling behavior" do
        error_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "ErrorAgent"

          def call
            raise StandardError, "Test error"
          end
        end

        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow standard_agent_class >> error_agent >> processor_agent_class
        end

        pipeline = pipeline_class.new

        expect { pipeline.run }.to raise_error(StandardError, "Test error")
      end

      it "handles errors in streaming agents appropriately" do
        error_streaming_agent = Class.new(streaming_agent_class) do
          def call
            raise StandardError, "Stream error" if context[:items].first[:id] == 5
            super
          end
        end

        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow standard_agent_class >> error_streaming_agent >> processor_agent_class
        end

        items = (1..20).map { |i| { id: i } }
        pipeline = pipeline_class.new(items: items)

        # Should handle error appropriately
        expect { pipeline.run }.to raise_error(StandardError, "Stream error")
      end
    end
  end
end