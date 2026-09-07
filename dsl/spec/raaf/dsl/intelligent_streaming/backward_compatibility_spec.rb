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

# Declaring intelligent_streaming on an agent must not change how that agent, or
# any pipeline it takes part in, behaves when the pipeline itself does not drive
# streaming.
RSpec.describe "IntelligentStreaming Backward Compatibility" do
  let(:context_class) { RAAF::DSL::ContextVariables }

  # Standard agents without intelligent streaming
  let(:standard_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "StandardAgent"
      model "gpt-4o"

      context do
        output :processed, :agent_name
      end

      def self.name
        "StandardAgent"
      end

      def run
        { processed: true, agent_name: self.class.name }
      end
    end
  end

  let(:processor_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ProcessorAgent"
      model "gpt-4o"

      context do
        output :items, :processor_run
      end

      def self.name
        "ProcessorAgent"
      end

      def run
        items = Array(context[:items]).map { |item| item.merge(processed: true) }
        { items: items, processor_run: true }
      end
    end
  end

  # Records the size of every chunk the batched agent is handed.
  let(:chunk_sizes) { [] }

  # Agent with in_chunks_of batching (existing feature)
  let(:chunked_agent_class) do
    sizes = chunk_sizes

    Class.new(RAAF::DSL::Agent) do
      agent_name "ChunkedAgent"
      model "gpt-4o"

      context do
        output :items
      end

      def self.name
        "ChunkedAgent"
      end

      define_method :run do
        items = Array(context[:items])
        sizes << items.size
        { items: items }
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

      context do
        output :stream_processed
      end

      def self.name
        "StreamingAgent"
      end

      def run
        { stream_processed: true }
      end
    end
  end

  describe "existing pipelines" do
    context "pipelines without intelligent_streaming" do
      it "works unchanged without intelligent_streaming" do
        agents = [standard_agent_class, processor_agent_class]
        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> agents[1]

          context do
            optional items: []
          end
        end

        items = (1..20).map { |i| { id: i } }
        result = pipeline_class.new(items: items).run

        expect(result[:processed]).to be true
        expect(result[:processor_run]).to be true
        expect(result[:items].all? { |item| item[:processed] }).to be true
      end

      it "does not create a streaming scope" do
        agents = [standard_agent_class, processor_agent_class]
        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> agents[1]
        end

        pipeline = pipeline_class.new(items: [])

        expect(pipeline.streaming_scopes).to be_empty
      end
    end

    context "with in_chunks_of agent batching" do
      it "works with in_chunks_of agent batching" do
        batched_agent = chunked_agent_class.in_chunks_of(5, input_field: :items, output_field: :items)

        items = (1..20).map { |i| { id: i } }
        result = batched_agent.execute(context_class.new(items: items))

        # Batching hands the agent one chunk at a time and stitches the array
        # back together.
        expect(chunk_sizes).to eq([5, 5, 5, 5])
        expect(result[:items].size).to eq(20)
      end

      it "allows in_chunks_of and intelligent_streaming in same pipeline" do
        chunked = chunked_agent_class.in_chunks_of(5, input_field: :items, output_field: :items)
        agents = [chunked, streaming_agent_class, processor_agent_class]
        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> agents[1] >> agents[2]

          context do
            optional items: []
          end
        end

        items = (1..30).map { |i| { id: i } }
        result = pipeline_class.new(items: items).run

        expect(chunk_sizes).to eq([5, 5, 5, 5, 5, 5])
        expect(result[:stream_processed]).to be true
        expect(result[:processor_run]).to be true
      end
    end
  end

  describe "existing agents" do
    context "agents without streaming config" do
      it "agents without streaming config work unchanged" do
        result = standard_agent_class.new(data: "test").run

        expect(result[:processed]).to be true
        expect(result[:agent_name]).to eq("StandardAgent")
      end

      it "reports no streaming configuration" do
        expect(standard_agent_class).to respond_to(:_intelligent_streaming_config)
        expect(standard_agent_class._intelligent_streaming_config).to be_nil
        expect(standard_agent_class.streaming_trigger?).to be false
      end

      it "reports a streaming configuration on an agent that declares one" do
        expect(streaming_agent_class._intelligent_streaming_config).not_to be_nil
        expect(streaming_agent_class.streaming_trigger?).to be true
      end

      it "does not hand the configuration down to subclasses" do
        subclass = Class.new(streaming_agent_class)

        expect(subclass._intelligent_streaming_config).to be_nil
      end
    end

    context "mixed pipelines" do
      it "works with mixed streaming and non-streaming agents" do
        agents = [standard_agent_class, streaming_agent_class, processor_agent_class]
        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> agents[1] >> agents[2]

          context do
            optional items: []
          end
        end

        items = (1..50).map { |i| { id: i } }
        result = pipeline_class.new(items: items).run

        expect(result[:processed]).to be true
        expect(result[:stream_processed]).to be true
        expect(result[:processor_run]).to be true
        expect(result[:items].size).to eq(50)
      end

      it "preserves execution order with mixed agents" do
        execution_order = []

        tracking = lambda do |parent, label|
          Class.new(parent) do
            define_method :run do
              execution_order << label
              super()
            end
          end
        end

        agents = [
          tracking.call(standard_agent_class, :standard),
          tracking.call(streaming_agent_class, :streaming),
          tracking.call(processor_agent_class, :processor)
        ]

        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> agents[1] >> agents[2]
        end

        items = (1..20).map { |i| { id: i } }
        pipeline_class.new(items: items).run

        expect(execution_order).to eq(%i[standard streaming processor])
      end
    end
  end

  describe "existing operators" do
    context ">> operator (sequential)" do
      it ">> operator works with streaming" do
        agents = [standard_agent_class, streaming_agent_class, processor_agent_class]
        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> agents[1] >> agents[2]
        end

        items = (1..30).map { |i| { id: i } }
        result = pipeline_class.new(items: items).run

        expect(result[:processed]).to be true
        expect(result[:stream_processed]).to be true
        expect(result[:processor_run]).to be true
      end
    end

    context "| operator (parallel)" do
      let(:parallel_agent1) do
        Class.new(RAAF::DSL::Agent) do
          agent_name "ParallelOne"
          context { output :parallel1 }
          def run
            { parallel1: true }
          end
        end
      end

      let(:parallel_agent2) do
        Class.new(RAAF::DSL::Agent) do
          agent_name "ParallelTwo"
          context { output :parallel2 }
          def run
            { parallel2: true }
          end
        end
      end

      it "| operator works with streaming agents" do
        agents = [streaming_agent_class, parallel_agent1, parallel_agent2, processor_agent_class]
        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> (agents[1] | agents[2]) >> agents[3]
        end

        items = (1..20).map { |i| { id: i } }
        result = pipeline_class.new(items: items).run

        expect(result[:stream_processed]).to be true
        expect(result[:parallel1]).to be true
        expect(result[:parallel2]).to be true
        expect(result[:processor_run]).to be true
      end

      it "handles two streaming agents side by side" do
        streaming_one = Class.new(streaming_agent_class) do
          agent_name "StreamingOne"
          context { output :stream1 }
          def run
            { stream1: true }
          end
        end

        streaming_two = Class.new(streaming_agent_class) do
          agent_name "StreamingTwo"
          context { output :stream2 }
          def run
            { stream2: true }
          end
        end

        agents = [standard_agent_class, streaming_one, streaming_two, processor_agent_class]
        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> (agents[1] | agents[2]) >> agents[3]
        end

        items = (1..20).map { |i| { id: i } }
        result = pipeline_class.new(items: items).run

        expect(result[:processed]).to be true
        expect(result[:stream1]).to be true
        expect(result[:stream2]).to be true
        expect(result[:processor_run]).to be true
      end
    end

    context "complex operator combinations" do
      it "handles complex combinations of >> and |" do
        flagger = lambda do |name, field|
          Class.new(RAAF::DSL::Agent) do
            agent_name name
            context { output field }
            define_method(:run) { { field => true } }
          end
        end

        agents = [
          flagger.call("AgentOne", :agent1),
          streaming_agent_class,
          flagger.call("AgentTwo", :agent2),
          flagger.call("AgentThree", :agent3),
          processor_agent_class
        ]

        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> (agents[1] | agents[2]) >> agents[3] >> agents[4]
        end

        items = (1..15).map { |i| { id: i } }
        result = pipeline_class.new(items: items).run

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

          intelligent_streaming do
            stream_size 25
            over :records
          end

          def run
            { configured: true }
          end
        end

        expect(configured_agent.agent_name).to eq("ConfiguredAgent")
        expect(configured_agent.model).to eq("gpt-4o-mini")
        expect(configured_agent._intelligent_streaming_config.stream_size).to eq(25)
        expect(configured_agent._intelligent_streaming_config.array_field).to eq(:records)
      end
    end

    context "context handling" do
      it "preserves context through mixed pipeline" do
        agents = [standard_agent_class, streaming_agent_class, processor_agent_class]
        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> agents[1] >> agents[2]

          context do
            required :items
            optional metadata: {}
            output :metadata
          end
        end

        items = (1..30).map { |i| { id: i } }
        metadata = { source: "test", version: 1 }

        result = pipeline_class.new(items: items, metadata: metadata).run

        expect(result[:metadata][:source]).to eq("test")
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

          def run
            raise StandardError, "Test error"
          end
        end

        agents = [standard_agent_class, error_agent, processor_agent_class]
        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> agents[1] >> agents[2]
        end

        expect { pipeline_class.new(items: []).run }.to raise_error(StandardError, "Test error")
      end

      it "handles errors in streaming agents appropriately" do
        error_streaming_agent = Class.new(streaming_agent_class) do
          agent_name "ErrorStreamingAgent"

          def run
            raise StandardError, "Stream error"
          end
        end

        agents = [standard_agent_class, error_streaming_agent, processor_agent_class]
        pipeline_class = Class.new(RAAF::Pipeline) do
          flow agents[0] >> agents[1] >> agents[2]
        end

        items = (1..20).map { |i| { id: i } }

        expect { pipeline_class.new(items: items).run }.to raise_error(StandardError, "Stream error")
      end
    end
  end
end
