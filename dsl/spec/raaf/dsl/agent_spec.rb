# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Agent do
  # Test agent classes
  class BasicTestAgent < described_class
    agent_name "BasicTestAgent"
    model "gpt-4o"
    
    def build_instructions
      "You are a basic test assistant."
    end
    
    def build_schema
      {
        type: "object",
        properties: {
          message: { type: "string" }
        },
        required: ["message"],
        additionalProperties: false
      }
    end
  end
  
  class SmartTestAgent < described_class
    agent_name "SmartTestAgent"
    model "gpt-4o-mini"
    max_turns 5
    temperature 0.7
    
    # Smart features
    requires :api_key, :endpoint
    validates :api_key, type: String, presence: true
    validates :endpoint, type: String
    
    retry_on :rate_limit, max_attempts: 3, backoff: :exponential
    retry_on Timeout::Error, max_attempts: 2
    circuit_breaker threshold: 5, timeout: 60, reset_timeout: 300
    
    schema do
      field :status, type: :string, required: true
      field :data, type: :array do
        field :id, type: :string
        field :value, type: :integer, range: 0..100
      end
    end
    
    system_prompt "You are a smart test assistant."
    
    user_prompt do |ctx|
      "Process endpoint #{ctx.get(:endpoint)} with key #{ctx.get(:api_key)[0..5]}..."
    end
  end
  
  class MinimalAgent < described_class
    def build_instructions
      "Minimal agent"
    end
    
    def build_schema
      nil # Test unstructured output
    end
  end
  
  describe "Basic Agent Functionality (from old Base)" do
    let(:context) { { test: true } }
    let(:agent) { BasicTestAgent.new(context: context) }
    
    describe "#initialize" do
      it "accepts context parameter" do
        expect { BasicTestAgent.new(context: context) }.not_to raise_error
      end
      
      it "accepts context_variables parameter for compatibility" do
        expect { BasicTestAgent.new(context_variables: context) }.not_to raise_error
      end
      
      it "accepts processing_params" do
        agent = BasicTestAgent.new(context: context, processing_params: { foo: "bar" })
        expect(agent.processing_params).to eq({ foo: "bar" })
      end
      
      it "defaults to empty context when not provided" do
        agent = BasicTestAgent.new
        expect(agent.context).to be_a(RAAF::DSL::ContextVariables)
        expect(agent.context.to_h).to eq({})
      end
    end
    
    describe "#agent_name" do
      it "returns the configured agent name" do
        expect(agent.agent_name).to eq("BasicTestAgent")
      end
      
      it "falls back to class name if not configured" do
        minimal = MinimalAgent.new
        expect(minimal.agent_name).to eq("MinimalAgent")
      end
    end
    
    describe "#model_name" do
      it "returns the configured model" do
        expect(agent.model_name).to eq("gpt-4o")
      end
      
      it "defaults to gpt-4o if not configured" do
        minimal = MinimalAgent.new
        expect(minimal.model_name).to eq("gpt-4o")
      end
    end
    
    describe "#build_instructions" do
      it "returns the system instructions" do
        expect(agent.build_instructions).to eq("You are a basic test assistant.")
      end
    end
    
    describe "#build_schema" do
      it "returns the response schema" do
        schema = agent.build_schema
        expect(schema[:type]).to eq("object")
        expect(schema[:properties][:message]).to eq({ type: "string" })
      end
      
      it "can return nil for unstructured output" do
        minimal = MinimalAgent.new
        expect(minimal.build_schema).to be_nil
      end
    end
    
    describe "#response_format" do
      it "returns structured format with schema" do
        format = agent.response_format
        expect(format[:type]).to eq("json_schema")
        expect(format[:json_schema][:strict]).to eq(true)
        expect(format[:json_schema][:schema]).to eq(agent.build_schema)
      end
      
      it "returns nil for unstructured output" do
        minimal = MinimalAgent.new
        expect(minimal.response_format).to be_nil
      end
    end
    
    describe "#create_agent" do
      it "creates a RAAF::Agent instance" do
        openai_agent = agent.create_agent
        expect(openai_agent).to be_a(RAAF::Agent)
        expect(openai_agent.name).to eq("BasicTestAgent")
        expect(openai_agent.model).to eq("gpt-4o")
      end
    end
  end
  
  describe "Smart Agent Features" do
    let(:valid_context) { { api_key: "sk-123456", endpoint: "https://api.example.com" } }
    let(:invalid_context) { { endpoint: "https://api.example.com" } }
    
    describe "Context Validation" do
      it "validates required context keys" do
        expect { SmartTestAgent.new(context: invalid_context) }
          .to raise_error(ArgumentError, /Required context keys missing: api_key/)
      end
      
      it "validates context value types" do
        invalid = { api_key: 123, endpoint: "test" }
        expect { SmartTestAgent.new(context: invalid) }
          .to raise_error(ArgumentError, /Context key 'api_key' must be String/)
      end
      
      it "accepts valid context" do
        expect { SmartTestAgent.new(context: valid_context) }.not_to raise_error
      end
    end
    
    describe "DSL Configuration" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      it "configures agent name" do
        expect(agent.agent_name).to eq("SmartTestAgent")
      end
      
      it "configures model" do
        expect(agent.model_name).to eq("gpt-4o-mini")
      end
      
      it "configures max_turns" do
        expect(agent.max_turns).to eq(5)
      end
      
      it "has retry configuration" do
        expect(SmartTestAgent._retry_config).to include(:rate_limit)
        expect(SmartTestAgent._retry_config[:rate_limit]).to include(
          max_attempts: 3,
          backoff: :exponential
        )
      end
      
      it "has circuit breaker configuration" do
        expect(SmartTestAgent._circuit_breaker_config).to include(
          threshold: 5,
          timeout: 60,
          reset_timeout: 300
        )
      end
    end
    
    describe "Schema DSL" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      it "builds schema from DSL" do
        schema = agent.build_schema
        
        expect(schema[:type]).to eq("object")
        expect(schema[:properties][:status]).to eq({ type: "string" })
        expect(schema[:properties][:data][:type]).to eq("array")
        expect(schema[:properties][:data][:items][:properties][:id]).to eq({ type: "string" })
        expect(schema[:required]).to include("status")
      end
    end
    
    describe "Prompt DSL" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      it "builds system prompt from string" do
        expect(agent.build_instructions).to eq("You are a smart test assistant.")
      end
      
      it "builds user prompt from block" do
        prompt = agent.build_user_prompt
        expect(prompt).to eq("Process endpoint https://api.example.com with key sk-123...")
      end
    end
    
    describe "#run with smart features" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      before do
        # Mock the direct_run method to simulate execution
        allow(agent).to receive(:direct_run).and_return({
          success: true,
          results: double(
            messages: [
              { role: "assistant", content: '{"status": "success", "data": []}' }
            ],
            final_output: '{"status": "success", "data": []}'
          )
        })
      end
      
      it "executes with retry and error handling when smart features configured" do
        result = agent.run
        expect(result).to include(success: true, data: { "status" => "success", "data" => [] })
      end
      
      it "logs execution start and completion for smart agents" do
        expect(RAAF::Logging).to receive(:info).with(/Starting execution/)
        expect(RAAF::Logging).to receive(:info).with(/completed successfully/)
        agent.run
      end
      
      it "skips smart features when skip_retries is true" do
        expect(agent).not_to receive(:check_circuit_breaker!)
        expect(agent).not_to receive(:execute_with_retry)
        agent.run(skip_retries: true)
      end
    end
    
    describe "#call method (backward compatibility)" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      it "delegates to run method" do
        expect(agent).to receive(:run).and_return({ success: true })
        result = agent.call
        expect(result).to eq({ success: true })
      end
    end
    
    describe "Error Handling" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      context "with rate limit error" do
        before do
          allow(agent).to receive(:direct_run).and_raise(StandardError.new("rate limit exceeded"))
        end
        
        it "categorizes rate limit errors" do
          result = agent.run
          expect(result[:error_type]).to eq("rate_limit")
          expect(result[:error]).to include("Rate limit exceeded")
        end
      end
      
      context "with JSON parse error" do
        before do
          allow(agent).to receive(:direct_run).and_raise(JSON::ParserError.new("unexpected token"))
        end
        
        it "categorizes JSON errors" do
          result = agent.run
          expect(result[:error_type]).to eq("json_error")
          expect(result[:error]).to include("Failed to parse AI response")
        end
      end
    end
  end
  
  describe "AgentDsl Integration" do
    it "includes AgentDsl automatically" do
      expect(described_class.ancestors).to include(RAAF::DSL::Agents::AgentDsl)
    end
    
    it "provides DSL methods without explicit include" do
      expect(described_class).to respond_to(:agent_name)
      expect(described_class).to respond_to(:model)
      expect(described_class).to respond_to(:uses_tool)
      expect(described_class).to respond_to(:schema)
    end
  end
  
  describe "AgentHooks Integration" do
    it "includes AgentHooks automatically" do
      expect(described_class.ancestors).to include(RAAF::DSL::Hooks::AgentHooks)
    end
    
    it "provides hook methods" do
      expect(described_class).to respond_to(:on_start)
      expect(described_class).to respond_to(:on_end)
      expect(described_class).to respond_to(:on_handoff)
    end
  end
  
  describe "Backward Compatibility" do
    it "works with old initialization style" do
      agent = BasicTestAgent.new(
        context_variables: { foo: "bar" },
        processing_params: { baz: "qux" }
      )
      expect(agent.context.to_h).to include(foo: "bar")
      expect(agent.processing_params).to eq({ baz: "qux" })
    end
    
    it "supports both run and call methods" do
      agent = BasicTestAgent.new(context: {})
      expect(agent).to respond_to(:run)
      expect(agent).to respond_to(:call)
    end
  end
  
  describe "Default Schema" do
    class DefaultSchemaAgent < described_class
      agent_name "DefaultAgent"
    end
    
    it "provides a default schema when not defined" do
      agent = DefaultSchemaAgent.new
      schema = agent.build_schema
      
      expect(schema[:type]).to eq("object")
      expect(schema[:properties]).to include(:result, :confidence)
      expect(schema[:required]).to include("result")
    end
  end
  
  describe "Configuration Inheritance" do
    class ParentAgent < described_class
      agent_name "ParentAgent"
      requires :user_id
      retry_on :network, max_attempts: 2
    end
    
    class ChildAgent < ParentAgent
      agent_name "ChildAgent"
      requires :session_id
    end
    
    it "inherits configuration from parent class" do
      expect(ChildAgent._required_context_keys).to include(:user_id, :session_id)
      expect(ChildAgent._retry_config).to include(:network)
    end
  end
end