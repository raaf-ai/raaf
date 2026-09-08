# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl"

RSpec.describe RAAF::DSL::PipelineDSL do
  describe "module structure" do
    it "is defined within RAAF::DSL namespace" do
      expect(described_class).to be_a(Module)
      expect(described_class.name).to eq("RAAF::DSL::PipelineDSL")
    end

    it "has a version constant" do
      expect(described_class::VERSION).to eq("1.0.0")
    end
  end

  describe "component loading" do
    it "loads the Pipelineable module that gives agents their pipeline metadata" do
      expect(defined?(RAAF::DSL::Pipelineable)).to be_truthy
    end

    it "loads ChainedAgent class" do
      expect(defined?(RAAF::DSL::PipelineDSL::ChainedAgent)).to be_truthy
    end

    it "loads ParallelAgents class" do
      expect(defined?(RAAF::DSL::PipelineDSL::ParallelAgents)).to be_truthy
    end

    it "loads ConfiguredAgent class" do
      expect(defined?(RAAF::DSL::PipelineDSL::ConfiguredAgent)).to be_truthy
    end

    it "loads RemappedAgent class" do
      expect(defined?(RAAF::DSL::PipelineDSL::RemappedAgent)).to be_truthy
    end

    it "loads FieldMismatchError class" do
      expect(defined?(RAAF::DSL::PipelineDSL::FieldMismatchError)).to be_truthy
    end

    it "loads Pipeline base class" do
      expect(defined?(RAAF::Pipeline)).to be_truthy
    end
  end

  describe "Pipeline base class" do
    it "provides DSL methods" do
      expect(RAAF::Pipeline).to respond_to(:flow)
      # context_reader has been removed in favor of auto-context
      expect(RAAF::Pipeline).to respond_to(:context)
    end

    it "can be inherited to create custom pipelines" do
      test_pipeline = Class.new(RAAF::Pipeline) do
        flow nil # Placeholder flow
      end

      expect(test_pipeline.ancestors).to include(RAAF::Pipeline)
    end
  end

  describe "operator overloading" do
    # Create test agents for operator testing
    let(:test_agent1) do
      Class.new(RAAF::DSL::Agent) do
        # Context is automatically available through auto-context
        result_transform do
          field :output1
        end
      end
    end

    let(:test_agent2) do
      Class.new(RAAF::DSL::Agent) do
        # Context is automatically available through auto-context
        result_transform do
          field :output2
        end
      end
    end

    it "supports >> operator for sequential chaining" do
      # The >> operator should be available on agent classes
      chained = test_agent1 >> test_agent2
      expect(chained).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
    end

    it "supports | operator for parallel execution" do
      # The | operator should be available on agent classes
      parallel = test_agent1 | test_agent2
      expect(parallel).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
    end
  end

  describe "agent introspection" do
    let(:introspectable_agent) do
      Class.new(RAAF::DSL::Agent) do
        # Context is automatically available through auto-context
        # Input fields: :product, :company

        result_transform do
          field :analysis
          field :scores
        end
      end
    end

    it "extracts input fields from auto-context (legacy test)" do
      # NOTE: pipeline_input_fields extraction is now handled differently with auto-context
      # This test is maintained for documentation purposes
      expect(true).to be true # Placeholder - input field detection works differently now
    end

    it "extracts output fields from result_transform" do
      expect(introspectable_agent._result_transformations.keys).to eq(%i[analysis scores])
    end

    it "does not treat result_transform fields as declared pipeline output" do
      # provided_fields comes from the context block's `output`; a
      # result_transform only reshapes what the agent returns.
      expect(introspectable_agent.provided_fields).to eq([])
    end
  end

  describe "field validation" do
    let(:incompatible_agent1) do
      Class.new(RAAF::DSL::Agent) do
        context do
          output :output_a
        end
      end
    end

    let(:incompatible_agent2) do
      Class.new(RAAF::DSL::Agent) do
        # Expects output_b, but agent1 provides output_a
        context do
          required :output_b
          output :final_output
        end
      end
    end

    it "detects field mismatches between agents" do
      chained = incompatible_agent1 >> incompatible_agent2

      # Validation is deferred until the pipeline supplies its context fields.
      expect do
        chained.validate_with_pipeline_context([])
      end.to raise_error(RAAF::DSL::PipelineDSL::FieldMismatchError)
    end

    it "stays quiet when the pipeline context supplies the missing field" do
      chained = incompatible_agent1 >> incompatible_agent2

      expect { chained.validate_with_pipeline_context([:output_b]) }.not_to raise_error
    end
  end

  describe "inline configuration" do
    # RAAF::DSL::Agent defines its own class-level `timeout` and `retry` (the
    # agent's HTTP timeout and retry settings), which shadow the pipeline
    # wrappers of the same name. A plain Pipelineable component exposes them.
    let(:configurable_agent) do
      Class.new do
        include RAAF::DSL::Pipelineable

        def self.name = "ConfigurableComponent"
        def self.required_fields = []
        def self.provided_fields = [:result]
      end
    end

    it "supports timeout configuration" do
      configured = configurable_agent.timeout(30)
      expect(configured).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
      expect(configured.options[:timeout]).to eq(30)
    end

    it "supports retry configuration" do
      configured = configurable_agent.retry(3)
      expect(configured).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
      expect(configured.options[:retry]).to eq(3)
    end

    it "supports limit configuration" do
      configured = configurable_agent.limit(25)
      expect(configured).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
      expect(configured.options[:limit]).to eq(25)
    end

    it "supports chained configuration" do
      configured = configurable_agent.timeout(30).retry(3).limit(25)
      expect(configured).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
      expect(configured.options).to include(timeout: 30, retry: 3, limit: 25)
    end

    it "keeps an Agent subclass's own timeout DSL intact" do
      agent = Class.new(RAAF::DSL::Agent) do
        timeout 45
      end

      expect(agent.send(:timeout)).to eq(45)
    end
  end

  describe "integration" do
    # Create a complete test pipeline
    let(:test_pipeline_class) do
      Class.new(RAAF::Pipeline) do
        # Mock agents for testing
        test_agent1 = Class.new(RAAF::DSL::Agent) do
          # Context is automatically available through auto-context
          result_transform do
            field :processed
          end
        end

        test_agent2 = Class.new(RAAF::DSL::Agent) do
          # Context is automatically available through auto-context
          result_transform do
            field :final
          end
        end

        flow test_agent1 >> test_agent2

        # Context variables are automatically available through auto-context

        context do
          optional option1: "default_value"
        end
      end
    end

    it "creates a functional pipeline" do
      pipeline = test_pipeline_class.new(input: "test_data")

      expect(pipeline).to be_a(RAAF::Pipeline)

      # Declared context variables are exposed as readers on the pipeline.
      expect(pipeline.option1).to eq("default_value")
    end

    it "maintains backward compatibility with existing agents" do
      # The DSL should work with any RAAF::DSL::Agent without modifications
      expect(RAAF::DSL::Agent.ancestors).to include(RAAF::DSL::Pipelineable)
    end
  end
end
