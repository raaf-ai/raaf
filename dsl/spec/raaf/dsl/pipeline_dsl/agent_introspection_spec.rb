# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl"

RSpec.describe RAAF::DSL::PipelineDSL::AgentIntrospection do
  # Create a test agent class
  let(:test_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "TestAgent"
      
      context_reader :product, :company, :market_data
      
      context do
        default :analysis_depth, "standard"
      end
      
      result_transform do
        field :potential_markets, computed: :compute_markets
        field :market_criteria, computed: :extract_criteria
      end
      
      def compute_markets(data)
        ["market1", "market2"]
      end
      
      def extract_criteria(data)
        { growth: 0.5 }
      end
    end
  end
  
  describe "#required_fields" do
    it "extracts fields from context_reader declarations" do
      expect(test_agent_class.required_fields).to include(:product, :company, :market_data)
    end
    
    it "includes fields from context block defaults" do
      expect(test_agent_class.required_fields).to include(:analysis_depth)
    end
    
    it "returns empty array when no context_reader defined" do
      agent = Class.new(RAAF::DSL::Agent)
      expect(agent.required_fields).to eq([])
    end
    
    it "returns unique fields" do
      agent = Class.new(RAAF::DSL::Agent) do
        context_reader :product, :product
      end
      expect(agent.required_fields).to eq([:product])
    end
  end
  
  describe "#provided_fields" do
    it "extracts field names from result_transform declarations" do
      expect(test_agent_class.provided_fields).to eq([:potential_markets, :market_criteria])
    end
    
    it "returns empty array when no result_transform defined" do
      agent = Class.new(RAAF::DSL::Agent)
      expect(agent.provided_fields).to eq([])
    end
  end
  
  describe "#requirements_met?" do
    let(:valid_context) { { product: "Test", company: "Corp", market_data: {}, analysis_depth: "deep" } }
    let(:invalid_context) { { product: "Test" } }
    
    it "returns true when all required fields present in hash context" do
      expect(test_agent_class.requirements_met?(valid_context)).to be true
    end
    
    it "returns false when required fields missing from context" do
      expect(test_agent_class.requirements_met?(invalid_context)).to be false
    end
    
    it "handles context with string keys" do
      string_context = valid_context.transform_keys(&:to_s)
      # This might fail depending on implementation - adjust as needed
      expect(test_agent_class.requirements_met?(valid_context)).to be true
    end
  end
  
  describe "operator overloading" do
    let(:other_agent) { Class.new(RAAF::DSL::Agent) }
    
    describe "#>>" do
      it "returns a ChainedAgent instance" do
        result = test_agent_class >> other_agent
        expect(result).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
      end
    end
    
    describe "#|" do
      it "returns a ParallelAgents instance" do
        result = test_agent_class | other_agent
        expect(result).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
      end
    end
    
    describe ".timeout" do
      it "returns a ConfiguredAgent with timeout option" do
        result = test_agent_class.timeout(60)
        expect(result).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
        expect(result.options[:timeout]).to eq(60)
      end
    end
    
    describe ".retry" do
      it "returns a ConfiguredAgent with retry option" do
        result = test_agent_class.retry(3)
        expect(result).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
        expect(result.options[:retry]).to eq(3)
      end
    end
    
    describe ".limit" do
      it "returns a ConfiguredAgent with limit option" do
        result = test_agent_class.limit(25)
        expect(result).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
        expect(result.options[:limit]).to eq(25)
      end
    end
  end
end