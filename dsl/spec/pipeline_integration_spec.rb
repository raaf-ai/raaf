# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Pipeline Integration with Service Classes" do
  # Test service classes
  let(:mock_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "MockAgent"
      
      context do
        required :input
        optional output: "default"
      end

      def self.provided_fields
        [:agent_result]
      end

      static_instructions "Mock agent instructions"
    end
  end

  let(:mock_service_class) do
    Class.new(RAAF::DSL::Service) do
      context do
        required :data
        optional multiplier: 2
      end

      def self.provided_fields
        [:service_result, :processed_count]
      end

      def call
        {
          service_result: data.map { |item| item * multiplier },
          processed_count: data.length
        }
      end
    end
  end

  let(:another_service_class) do
    Class.new(RAAF::DSL::Service) do
      context do
        required :service_result
      end

      def self.provided_fields
        [:final_result]
      end

      def call
        {
          final_result: service_result.sum
        }
      end
    end
  end

  # Test pipeline class
  let(:test_pipeline_class) do
    Class.new(RAAF::Pipeline) do
      # Mix agents and services in the pipeline
      flow MockAgent >> MockService >> AnotherService

      context do
        required :input, :data
      end
    end
  end

  before do
    stub_const("MockAgent", mock_agent_class)
    stub_const("MockService", mock_service_class)  
    stub_const("AnotherService", another_service_class)
    stub_const("TestPipeline", test_pipeline_class)
  end

  describe "Pipeline DSL operators with services" do
    describe "chaining operator (>>)" do
      it "creates ChainedAgent with service classes" do
        chain = mock_service_class >> another_service_class
        
        expect(chain).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
        expect(chain.first).to eq(mock_service_class)
        expect(chain.second).to eq(another_service_class)
      end

      it "chains agents and services together" do
        chain = mock_agent_class >> mock_service_class >> another_service_class
        
        expect(chain).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
      end
    end

    describe "parallel operator (|)" do
      it "creates ParallelAgents with service classes" do
        parallel = mock_service_class | another_service_class
        
        expect(parallel).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
        expect(parallel.agents).to include(mock_service_class, another_service_class)
      end
    end

    describe "iterator pattern" do
      it "creates IteratingAgent with service class" do
        iterator = mock_service_class.each_over(:items)
        
        expect(iterator).to be_a(RAAF::DSL::PipelineDSL::IteratingAgent)
        expect(iterator.agent_class).to eq(mock_service_class)
        expect(iterator.field).to eq(:items)
      end

      it "supports parallel iteration" do
        iterator = mock_service_class.each_over(:items).parallel
        
        expect(iterator.parallel?).to be_truthy
      end
    end

    describe "configuration methods" do
      it "wraps services with ConfiguredAgent" do
        configured = mock_service_class.timeout(60).retry(3).limit(10)
        
        expect(configured).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
        expect(configured.agent_class).to eq(mock_service_class)
        expect(configured.config[:timeout]).to eq(60)
        expect(configured.config[:retry]).to eq(3)
        expect(configured.config[:limit]).to eq(10)
      end
    end
  end

  describe "Pipeline execution with services" do
    let(:mock_pipeline_class) do
      Class.new(RAAF::Pipeline) do
        flow MockService
        
        context do
          required :data
        end
      end
    end

    before do
      stub_const("MockPipeline", mock_pipeline_class)
    end

    it "executes service classes correctly" do
      # Mock the pipeline execution to avoid complex dependencies
      pipeline = mock_pipeline_class.new(data: [1, 2, 3], multiplier: 3)
      
      # Test that the pipeline correctly identifies and executes the service
      expect(pipeline.send(:is_service_class?, mock_service_class)).to be_truthy
      expect(pipeline.send(:is_service_class?, mock_agent_class)).to be_falsey
    end

    it "calls 'call' method on service instances" do
      service_instance = mock_service_class.new(data: [1, 2, 3])
      
      result = service_instance.call
      
      expect(result[:service_result]).to eq([2, 4, 6])
      expect(result[:processed_count]).to eq(3)
    end
  end

  describe "Field validation and requirements" do
    describe "required_fields" do
      it "correctly identifies required fields for services" do
        expect(mock_service_class.required_fields).to include(:data, :multiplier)
      end

      it "correctly identifies externally required fields" do
        expect(mock_service_class.externally_required_fields).to eq([:data])
      end
    end

    describe "provided_fields" do
      it "identifies fields provided by services" do
        expect(mock_service_class.provided_fields).to eq([:service_result, :processed_count])
        expect(another_service_class.provided_fields).to eq([:final_result])
      end
    end

    describe "requirements_met?" do
      it "validates service requirements correctly" do
        valid_context = { data: [1, 2, 3], multiplier: 2 }
        invalid_context = { multiplier: 2 } # missing required 'data'
        
        expect(mock_service_class.requirements_met?(valid_context)).to be_truthy
        expect(mock_service_class.requirements_met?(invalid_context)).to be_falsey
      end

      it "considers defaults when checking requirements" do
        context_with_defaults = { data: [1, 2, 3] } # multiplier has default
        
        expect(mock_service_class.requirements_met?(context_with_defaults)).to be_truthy
      end
    end
  end

  describe "Mixed agent-service pipelines" do
    let(:mixed_pipeline_class) do
      Class.new(RAAF::Pipeline) do
        # Agent -> Service -> Service chain
        flow MockAgent >> MockService >> AnotherService
        
        context do
          required :input, :data
        end
      end
    end

    before do
      stub_const("MixedPipeline", mixed_pipeline_class)
    end

    it "handles mixed agent and service types in flow" do
      pipeline = mixed_pipeline_class.new(input: "test", data: [1, 2])
      
      # Should correctly identify different class types
      expect(pipeline.send(:is_service_class?, mock_service_class)).to be_truthy
      expect(pipeline.send(:is_service_class?, another_service_class)).to be_truthy
      expect(pipeline.send(:is_service_class?, mock_agent_class)).to be_falsey
    end
  end

  describe "Error handling in service execution" do
    let(:failing_service_class) do
      Class.new(RAAF::DSL::Service) do
        context do
          required :input
        end

        def call
          raise StandardError, "Service execution failed"
        end
      end
    end

    before do
      stub_const("FailingService", failing_service_class)
    end

    it "propagates service execution errors" do
      service = failing_service_class.new(input: "test")
      
      expect { service.call }.to raise_error(StandardError, "Service execution failed")
    end
  end

  describe "Context passing between agents and services" do
    it "services receive context variables from previous steps" do
      # Service should be able to access context set by previous pipeline steps
      service = mock_service_class.new(data: [1, 2, 3], multiplier: 5)
      
      expect(service.data).to eq([1, 2, 3])
      expect(service.multiplier).to eq(5)
    end

    it "services can provide fields for subsequent steps" do
      first_service = mock_service_class.new(data: [1, 2])
      result = first_service.call
      
      second_service = another_service_class.new(service_result: result[:service_result])
      final_result = second_service.call
      
      expect(final_result[:final_result]).to eq(6) # [2, 4].sum
    end
  end

  describe "Service inheritance and shared modules" do
    it "services inherit from RAAF::DSL::Service" do
      expect(mock_service_class.ancestors).to include(RAAF::DSL::Service)
    end

    it "services include context configuration module" do
      expect(mock_service_class.ancestors).to include(RAAF::DSL::ContextConfiguration)
    end

    it "services include pipeline integration module" do
      expect(mock_service_class.ancestors).to include(RAAF::DSL::PipelineIntegration)
    end

    it "services include context access module" do
      expect(mock_service_class.ancestors).to include(RAAF::DSL::ContextAccess)
    end
  end
end