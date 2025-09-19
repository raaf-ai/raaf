# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Pipelineable do
  # Test classes that include Pipelineable
  class TestPipelineableAgent
    include RAAF::DSL::Pipelineable

    def self.required_fields
      [:input_data]
    end

    def self.provided_fields
      [:processed_data]
    end

    def initialize(context = {})
      @context = context
    end

    attr_reader :context

    def pipeline_component_type
      :agent
    end
  end

  class TestPipelineableService
    include RAAF::DSL::Pipelineable

    def self.required_fields
      [:service_input]
    end

    def self.provided_fields
      [:service_output]
    end

    def initialize(context = {})
      @context = context
    end

    attr_reader :context

    def pipeline_component_type
      :service
    end
  end

  describe "DSL operators" do
    describe ">>" do
      it "creates a chained agent" do
        chained = TestPipelineableAgent >> TestPipelineableService
        expect(chained).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
        expect(chained.first_agent).to eq(TestPipelineableAgent)
        expect(chained.second_agent).to eq(TestPipelineableService)
      end

      it "passes pipeline context fields when available" do
        Thread.current[:raaf_pipeline_context_fields] = [:shared_field]
        chained = TestPipelineableAgent >> TestPipelineableService
        expect(chained.pipeline_context_fields).to include(:shared_field)
      ensure
        Thread.current[:raaf_pipeline_context_fields] = nil
      end

      it "creates nested chains for multiple agents" do
        triple = TestPipelineableAgent >> TestPipelineableService >> TestPipelineableAgent
        expect(triple).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
      end
    end

    describe "|" do
      it "creates parallel agents" do
        parallel = TestPipelineableAgent | TestPipelineableService
        expect(parallel).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
        expect(parallel.agents).to include(TestPipelineableAgent, TestPipelineableService)
      end

      it "combines multiple parallel agents" do
        triple_parallel = TestPipelineableAgent | TestPipelineableService | TestPipelineableAgent
        expect(triple_parallel).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
        expect(triple_parallel.agents.length).to eq(3)
      end
    end

    describe "configuration methods" do
      it "creates configured agent with timeout" do
        configured = TestPipelineableAgent.timeout(30)
        expect(configured).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
        expect(configured.configuration[:timeout]).to eq(30)
        expect(configured.agent_class).to eq(TestPipelineableAgent)
      end

      it "creates configured agent with retry" do
        configured = TestPipelineableAgent.retry(3)
        expect(configured).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
        expect(configured.configuration[:retry]).to eq(3)
      end

      it "creates configured agent with limit" do
        configured = TestPipelineableAgent.limit(100)
        expect(configured).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
        expect(configured.configuration[:limit]).to eq(100)
      end

      it "chains multiple configurations" do
        configured = TestPipelineableAgent.timeout(30).retry(3).limit(100)
        expect(configured).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
        expect(configured.configuration).to include(
          timeout: 30,
          retry: 3,
          limit: 100
        )
      end
    end

    describe "iteration support" do
      it "creates iterating agent with simple syntax" do
        iterating = TestPipelineableAgent.each_over(:items)
        expect(iterating).to be_a(RAAF::DSL::PipelineDSL::IteratingAgent)
        expect(iterating.field).to eq(:items)
        expect(iterating.agent_class).to eq(TestPipelineableAgent)
      end

      it "creates iterating agent with custom output field" do
        iterating = TestPipelineableAgent.each_over(:items, to: :results)
        expect(iterating).to be_a(RAAF::DSL::PipelineDSL::IteratingAgent)
        expect(iterating.field).to eq(:items)
        expect(iterating.options[:to]).to eq(:results)
      end

      it "creates iterating agent with :from marker syntax" do
        iterating = TestPipelineableAgent.each_over(:from, :items, to: :results)
        expect(iterating).to be_a(RAAF::DSL::PipelineDSL::IteratingAgent)
        expect(iterating.field).to eq(:items)
        expect(iterating.options[:to]).to eq(:results)
      end

      it "raises error for invalid iteration syntax" do
        expect {
          TestPipelineableAgent.each_over(:from, :items, :results)
        }.to raise_error(ArgumentError, /Invalid syntax/)

        expect {
          TestPipelineableAgent.each_over(:from, :items)
        }.to raise_error(ArgumentError, /:from marker requires 'to:' keyword argument/)

        expect {
          TestPipelineableAgent.each_over
        }.to raise_error(ArgumentError, /Invalid each_over syntax/)
      end

      it "supports iteration options" do
        iterating = TestPipelineableAgent.each_over(:items, as: :item, to: :processed_items)
        expect(iterating.options[:as]).to eq(:item)
        expect(iterating.options[:to]).to eq(:processed_items)
      end
    end

    describe "parameter remapping" do
      it "creates remapped agent with input mapping" do
        remapped = TestPipelineableAgent.with_mapping(processed_data: :input_data)
        expect(remapped).to be_a(RAAF::DSL::PipelineDSL::RemappedAgent)
        expect(remapped.input_mapping).to eq(processed_data: :input_data)
        expect(remapped.agent_class).to eq(TestPipelineableAgent)
      end

      it "creates remapped agent with full syntax" do
        remapped = TestPipelineableAgent.with_mapping(
          input: { processed_data: :input_data },
          output: { results: :processed_results }
        )
        expect(remapped).to be_a(RAAF::DSL::PipelineDSL::RemappedAgent)
        expect(remapped.input_mapping).to eq(processed_data: :input_data)
        expect(remapped.output_mapping).to eq(results: :processed_results)
      end

      it "extracts DSL configurations for remapped agents" do
        # Test with a class that has DSL config
        class ConfiguredPipelineableAgent
          include RAAF::DSL::Pipelineable

          def self._context_config
            { timeout: 60, retry: 2, max_turns: 3 }
          end
        end

        config = ConfiguredPipelineableAgent.extract_agent_dsl_config
        expect(config).to include(timeout: 60, retry: 2, max_turns: 3)
      end

      it "handles agents without DSL config" do
        config = TestPipelineableAgent.extract_agent_dsl_config
        expect(config).to eq({})
      end
    end
  end

  describe "requirement checking" do
    describe "#requirements_met?" do
      it "returns true when all requirements are met" do
        context = { input_data: ["test"] }
        expect(TestPipelineableAgent.requirements_met?(context)).to be true
      end

      it "returns false when requirements are missing" do
        context = { other_field: "value" }
        expect(TestPipelineableAgent.requirements_met?(context)).to be false
      end

      it "supports both string and symbol keys" do
        symbol_context = { input_data: ["test"] }
        string_context = { "input_data" => ["test"] }

        expect(TestPipelineableAgent.requirements_met?(symbol_context)).to be true
        expect(TestPipelineableAgent.requirements_met?(string_context)).to be true
      end

      it "handles context objects with keys method" do
        context_like = double("context_like")
        allow(context_like).to receive(:keys).and_return([:input_data])

        expect(TestPipelineableAgent.requirements_met?(context_like)).to be true
      end

      it "handles context variables objects" do
        context_vars = RAAF::DSL::ContextVariables.new(input_data: ["test"])
        expect(TestPipelineableAgent.requirements_met?(context_vars)).to be true
      end

      it "considers default values when available" do
        # Test with class that has default values
        class AgentWithDefaults
          include RAAF::DSL::Pipelineable

          def self.required_fields
            [:required_field]
          end

          def self._context_config
            {
              context_rules: {
                defaults: { required_field: "default_value" }
              }
            }
          end
        end

        empty_context = {}
        expect(AgentWithDefaults.requirements_met?(empty_context)).to be true
      end

      it "returns true for agents with no requirements" do
        class NoRequirementsAgent
          include RAAF::DSL::Pipelineable

          def self.required_fields
            []
          end
        end

        expect(NoRequirementsAgent.requirements_met?({})).to be true
      end
    end
  end

  describe "field introspection" do
    it "reports required fields" do
      expect(TestPipelineableAgent.required_fields).to eq([:input_data])
    end

    it "reports provided fields" do
      expect(TestPipelineableAgent.provided_fields).to eq([:processed_data])
    end

    it "handles externally required fields" do
      class ExternalFieldsAgent
        include RAAF::DSL::Pipelineable

        def self.externally_required_fields
          [:external_field1, :external_field2]
        end
      end

      expect(ExternalFieldsAgent.required_fields).to eq([:external_field1, :external_field2])
    end

    it "handles output fields from context configuration" do
      class OutputConfigAgent
        include RAAF::DSL::Pipelineable

        def self._context_config
          {
            context_rules: {
              output: [:config_output1, :config_output2]
            }
          }
        end
      end

      expect(OutputConfigAgent.provided_fields).to eq([:config_output1, :config_output2])
    end

    it "falls back to declared provided fields" do
      class DeclaredFieldsAgent
        include RAAF::DSL::Pipelineable

        def self.declared_provided_fields
          [:declared_field1, :declared_field2]
        end
      end

      expect(DeclaredFieldsAgent.provided_fields).to eq([:declared_field1, :declared_field2])
    end
  end

  describe "instance methods" do
    let(:instance) { TestPipelineableAgent.new(input_data: ["test"]) }

    describe "#can_validate_for_pipeline?" do
      it "returns true when validation method exists" do
        allow(instance).to receive(:respond_to?).with(:validate_for_pipeline, true).and_return(true)
        expect(instance.can_validate_for_pipeline?).to be true
      end

      it "returns false when validation method doesn't exist" do
        allow(instance).to receive(:respond_to?).with(:validate_for_pipeline, true).and_return(false)
        expect(instance.can_validate_for_pipeline?).to be false
      end
    end

    describe "#validate_for_pipeline" do
      it "validates required context fields" do
        valid_context = { input_data: ["test"] }
        expect { instance.validate_for_pipeline(valid_context) }.not_to raise_error
      end

      it "raises error for missing required fields" do
        invalid_context = { other_field: "value" }
        expect { instance.validate_for_pipeline(invalid_context) }
          .to raise_error(RAAF::DSL::Error, /missing required context fields/)
      end

      it "considers default values during validation" do
        # Mock defaults
        allow(TestPipelineableAgent).to receive(:_context_config).and_return({
          context_rules: { defaults: { input_data: ["default"] } }
        })

        empty_context = {}
        expect { instance.validate_for_pipeline(empty_context) }.not_to raise_error
      end

      it "provides detailed error messages" do
        invalid_context = { wrong_field: "value" }
        expect { instance.validate_for_pipeline(invalid_context) }
          .to raise_error(RAAF::DSL::Error) do |error|
            expect(error.message).to include("TestPipelineableAgent")
            expect(error.message).to include("input_data")
            expect(error.message).to include("wrong_field")
          end
      end
    end

    describe "#pipeline_component_type" do
      it "identifies agent components" do
        expect(instance.pipeline_component_type).to eq(:agent)
      end

      it "identifies service components" do
        service_instance = TestPipelineableService.new
        expect(service_instance.pipeline_component_type).to eq(:service)
      end

      it "identifies other components" do
        class OtherComponent
          include RAAF::DSL::Pipelineable
        end

        other_instance = OtherComponent.new
        expect(other_instance.pipeline_component_type).to eq(:other)
      end
    end
  end

  describe "complex pipeline scenarios" do
    it "handles nested pipeline structures" do
      nested = TestPipelineableAgent >> (TestPipelineableService | TestPipelineableAgent)
      expect(nested).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
      expect(nested.second_agent).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
    end

    it "handles configured parallel agents" do
      configured_parallel = TestPipelineableAgent.timeout(30) | TestPipelineableService.retry(3)
      expect(configured_parallel).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
    end

    it "handles chained configured agents" do
      chained_configured = TestPipelineableAgent.timeout(30) >> TestPipelineableService.retry(3)
      expect(chained_configured).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
    end

    it "handles iteration with configuration" do
      iteration_config = TestPipelineableAgent.each_over(:items).timeout(60)
      expect(iteration_config).to be_a(RAAF::DSL::PipelineDSL::IteratingAgent)
    end
  end

  describe "error conditions" do
    it "handles validation errors gracefully" do
      instance = TestPipelineableAgent.new
      invalid_context = "not a hash"

      expect { instance.validate_for_pipeline(invalid_context) }
        .to raise_error(RAAF::DSL::Error)
    end

    it "handles missing field information gracefully" do
      class MinimalPipelineableComponent
        include RAAF::DSL::Pipelineable
      end

      expect(MinimalPipelineableComponent.required_fields).to eq([])
      expect(MinimalPipelineableComponent.provided_fields).to eq([])
      expect(MinimalPipelineableComponent.requirements_met?({})).to be true
    end
  end
end