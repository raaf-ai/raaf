# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/dsl/agents/smart_agent"

RSpec.describe RAAF::DSL::Agents::SmartAgent do
  # Test agent classes
  class TestSmartAgent < described_class
    agent_name "TestAgent"
    model "gpt-4o"
    requires :product, :company
    validates :product, presence: [:name]
    
    schema do
      field :result, type: :string, required: true
      field :confidence, type: :integer, range: 0..100
    end
    
    system_prompt "You are a test assistant."
    
    user_prompt do |ctx|
      "Test with product: #{ctx.product.name}"
    end
    
    retry_on :rate_limit, max_attempts: 3
    circuit_breaker threshold: 5
  end
  
  class MinimalSmartAgent < described_class
    agent_name "MinimalAgent"
  end
  
  class AdvancedSmartAgent < described_class
    agent_name "AdvancedAgent"
    requires :data
    
    system_prompt do |ctx|
      "Advanced agent for #{ctx.data.type}"
    end
    
    retry_on :rate_limit, max_attempts: 5, backoff: :exponential
    retry_on :timeout, max_attempts: 2, delay: 3
  end
  
  # Mock objects
  let(:product) { double("Product", name: "Test Product", description: "A test product") }
  let(:company) { double("Company", name: "Test Company") }
  let(:context) { { product: product, company: company } }
  
  describe ".agent_name" do
    it "sets the agent name" do
      expect(TestSmartAgent._agent_config[:name]).to eq("TestAgent")
    end
  end
  
  describe ".model" do
    it "sets the model name" do
      expect(TestSmartAgent._agent_config[:model]).to eq("gpt-4o")
    end
  end
  
  describe ".requires" do
    it "sets required context keys" do
      expect(TestSmartAgent._required_context_keys).to include(:product, :company)
    end
  end
  
  describe ".validates" do
    it "sets validation rules" do
      expect(TestSmartAgent._validation_rules[:product]).to eq(presence: [:name])
    end
  end
  
  describe ".schema" do
    it "builds schema from DSL" do
      schema = TestSmartAgent._schema_definition
      
      expect(schema[:type]).to eq("object")
      expect(schema[:properties][:result]).to eq(type: "string")
      expect(schema[:properties][:confidence]).to include(type: "integer", minimum: 0, maximum: 100)
      expect(schema[:required]).to include("result")
    end
  end
  
  describe ".system_prompt" do
    it "sets system prompt" do
      agent = TestSmartAgent.new(context: context)
      expect(agent.build_instructions).to eq("You are a test assistant.")
    end
    
    it "supports block-based prompts" do
      data = double("Data", type: "complex")
      agent = AdvancedSmartAgent.new(context: { data: data })
      expect(agent.build_instructions).to eq("Advanced agent for complex")
    end
  end
  
  describe ".user_prompt" do
    it "supports block-based user prompts" do
      agent = TestSmartAgent.new(context: context)
      expect(agent.build_user_prompt).to eq("Test with product: Test Product")
    end
  end
  
  describe ".retry_on" do
    it "configures retry behavior" do
      expect(TestSmartAgent._retry_config[:rate_limit]).to include(max_attempts: 3)
      expect(AdvancedSmartAgent._retry_config[:rate_limit]).to include(max_attempts: 5, backoff: :exponential)
      expect(AdvancedSmartAgent._retry_config[:timeout]).to include(max_attempts: 2, delay: 3)
    end
  end
  
  describe ".circuit_breaker" do
    it "configures circuit breaker" do
      expect(TestSmartAgent._circuit_breaker_config).to include(threshold: 5)
    end
  end
  
  describe "#initialize" do
    it "accepts context hash" do
      agent = TestSmartAgent.new(context: context)
      expect(agent.context.get(:product)).to eq(product)
    end
    
    it "accepts ContextVariables instance" do
      context_vars = RAAF::DSL::ContextVariables.new(context)
      agent = TestSmartAgent.new(context: context_vars)
      expect(agent.context.get(:product)).to eq(product)
    end
    
    it "validates required context keys" do
      expect {
        TestSmartAgent.new(context: { product: product })
      }.to raise_error(ArgumentError, /Required context keys missing: company/)
    end
    
    it "validates context rules" do
      invalid_product = double("Product", name: nil)
      expect {
        TestSmartAgent.new(context: { product: invalid_product, company: company })
      }.to raise_error(ArgumentError, /missing required attributes/)
    end
    
    it "works with minimal configuration" do
      expect {
        MinimalSmartAgent.new(context: {})
      }.not_to raise_error
    end
  end
  
  describe "#build_instructions" do
    it "returns configured system prompt" do
      agent = TestSmartAgent.new(context: context)
      expect(agent.build_instructions).to eq("You are a test assistant.")
    end
    
    it "returns default prompt when none configured" do
      agent = MinimalSmartAgent.new(context: {})
      expect(agent.build_instructions).to eq("You are a helpful AI assistant.")
    end
  end
  
  describe "#build_schema" do
    it "returns configured schema" do
      agent = TestSmartAgent.new(context: context)
      schema = agent.build_schema
      
      expect(schema[:properties][:result]).to eq(type: "string")
      expect(schema[:required]).to include("result")
    end
    
    it "returns default schema when none configured" do
      agent = MinimalSmartAgent.new(context: {})
      schema = agent.build_schema
      
      expect(schema[:properties][:result]).to eq(type: "string", description: "The result of the analysis")
      expect(schema[:required]).to include("result")
    end
  end
  
  describe "#build_user_prompt" do
    it "returns configured user prompt" do
      agent = TestSmartAgent.new(context: context)
      expect(agent.build_user_prompt).to eq("Test with product: Test Product")
    end
    
    it "returns default prompt when none configured" do
      agent = MinimalSmartAgent.new(context: {})
      expect(agent.build_user_prompt).to eq("Please help me with this task.")
    end
  end
  
  describe "#call" do
    let(:agent) { TestSmartAgent.new(context: context) }
    
    before do
      # Mock the RAAF run method
      allow(agent).to receive(:run).and_return(mock_raaf_result)
    end
    
    context "with successful execution" do
      let(:mock_raaf_result) do
        {
          success: true,
          results: double("Results", 
            final_output: { result: "Success", confidence: 95 }.to_json,
            messages: []
          )
        }
      end
      
      it "processes result successfully" do
        result = agent.call
        
        expect(result[:success]).to be true
        expect(result[:data][:result]).to eq("Success")
        expect(result[:data][:confidence]).to eq(95)
      end
    end
    
    context "with JSON parsing error" do
      let(:mock_raaf_result) do
        {
          success: true,
          results: double("Results", 
            final_output: "invalid json{",
            messages: []
          )
        }
      end
      
      it "handles JSON parsing errors" do
        result = agent.call
        
        expect(result[:success]).to be false
        expect(result[:error_type]).to eq("json_error")
        expect(result[:error]).to include("Failed to parse AI response")
      end
    end
    
    context "with rate limit error" do
      it "categorizes rate limit errors" do
        allow(agent).to receive(:run).and_raise(StandardError.new("rate limit exceeded"))
        
        result = agent.call
        
        expect(result[:success]).to be false
        expect(result[:error_type]).to eq("rate_limit")
        expect(result[:error]).to include("Rate limit exceeded")
      end
    end
    
    context "with validation error" do
      it "categorizes validation errors" do
        allow(agent).to receive(:run).and_raise(ArgumentError.new("Required context keys missing"))
        
        result = agent.call
        
        expect(result[:success]).to be false
        expect(result[:error_type]).to eq("validation_error")
      end
    end
    
    context "with unexpected error" do
      it "handles unexpected errors" do
        allow(agent).to receive(:run).and_raise(StandardError.new("Something went wrong"))
        
        result = agent.call
        
        expect(result[:success]).to be false
        expect(result[:error_type]).to eq("unexpected_error")
        expect(result[:error]).to include("Agent execution failed")
      end
    end
  end
  
  describe "retry functionality" do
    let(:agent) { TestSmartAgent.new(context: context) }
    
    it "retries on rate limit errors" do
      call_count = 0
      allow(agent).to receive(:run) do
        call_count += 1
        if call_count < 3
          raise StandardError.new("rate limit exceeded")
        else
          { success: true, results: double("Results", final_output: '{"result":"success"}', messages: []) }
        end
      end
      
      result = agent.call
      
      expect(result[:success]).to be true
      expect(call_count).to eq(3)
    end
    
    it "stops retrying after max attempts" do
      allow(agent).to receive(:run).and_raise(StandardError.new("rate limit exceeded"))
      
      result = agent.call
      
      expect(result[:success]).to be false
      expect(result[:error_type]).to eq("rate_limit")
    end
  end
  
  describe "circuit breaker functionality" do
    let(:agent) { TestSmartAgent.new(context: context) }
    
    it "opens circuit after threshold failures" do
      # Simulate failures to trip circuit breaker
      5.times { agent.send(:record_circuit_breaker_failure!) }
      
      expect(agent.instance_variable_get(:@circuit_breaker_state)).to eq(:open)
    end
    
    it "prevents execution when circuit is open" do
      agent.instance_variable_set(:@circuit_breaker_state, :open)
      agent.instance_variable_set(:@circuit_breaker_last_failure, Time.current)
      
      result = agent.call
      
      expect(result[:success]).to be false
      expect(result[:error_type]).to eq("circuit_breaker")
    end
  end
  
  describe "inheritance" do
    class ParentAgent < described_class
      agent_name "ParentAgent"
      requires :base_data
      retry_on :timeout, max_attempts: 2
    end
    
    class ChildAgent < ParentAgent
      agent_name "ChildAgent"
      requires :additional_data
      retry_on :rate_limit, max_attempts: 4
    end
    
    it "inherits configuration from parent" do
      expect(ChildAgent._required_context_keys).to include(:base_data, :additional_data)
      expect(ChildAgent._retry_config[:timeout]).to include(max_attempts: 2)
      expect(ChildAgent._retry_config[:rate_limit]).to include(max_attempts: 4)
    end
  end
  
  describe "SchemaBuilder" do
    describe "#field" do
      it "builds simple field definitions" do
        builder = described_class::SchemaBuilder.new do
          field :name, type: :string, required: true, description: "The name"
        end
        
        schema = builder.build
        expect(schema[:properties][:name]).to eq(
          type: "string",
          description: "The name"
        )
        expect(schema[:required]).to include("name")
      end
      
      it "handles integer fields with ranges" do
        builder = described_class::SchemaBuilder.new do
          field :score, type: :integer, range: 0..100
        end
        
        schema = builder.build
        expect(schema[:properties][:score]).to include(
          type: "integer",
          minimum: 0,
          maximum: 100
        )
      end
      
      it "handles array fields" do
        builder = described_class::SchemaBuilder.new do
          field :tags, type: :array, items_type: :string, min_items: 1
        end
        
        schema = builder.build
        expect(schema[:properties][:tags]).to include(
          type: "array",
          items: { type: "string" },
          minItems: 1
        )
      end
      
      it "handles nested object fields" do
        builder = described_class::SchemaBuilder.new do
          field :metadata, type: :object do
            field :created_at, type: :string
            field :version, type: :integer
          end
        end
        
        schema = builder.build
        metadata_schema = schema[:properties][:metadata]
        expect(metadata_schema[:properties][:created_at]).to eq(type: "string")
        expect(metadata_schema[:properties][:version]).to eq(type: "integer")
      end
    end
  end
end