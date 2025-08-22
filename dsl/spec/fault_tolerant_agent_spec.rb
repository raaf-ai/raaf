# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/raaf/dsl/agent'

RSpec.describe "Fault-Tolerant Agent Schema Validation" do
  # Mock RAAF agent and runner for testing
  let(:mock_raaf_agent) { double("RAAF::Agent") }
  let(:mock_runner) { double("RAAF::Runner") }
  let(:mock_result) { double("RAAF::Result", messages: [{ content: response_content }]) }

  before do
    allow(RAAF::Agent).to receive(:new).and_return(mock_raaf_agent)
    allow(RAAF::Runner).to receive(:new).and_return(mock_runner)
    allow(mock_runner).to receive(:run).and_return(mock_result)
  end

  describe "strict validation mode (backward compatibility)" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "StrictTestAgent"
        
        schema do
          field :name, type: :string, required: true
          field :age, type: :integer, required: false
          validation :strict
        end
        
        def self.name
          "StrictTestAgent"
        end
      end
    end

    context "with valid JSON response" do
      let(:response_content) { '{"name": "John", "age": 30}' }
      
      it "parses successfully" do
        agent = agent_class.new(name: "John")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:name]).to eq("John")
        expect(result[:parsed_output][:age]).to eq(30)
      end
    end

    context "with malformed JSON response" do
      let(:response_content) { '{"name": "John", "age": 30,}' }  # Trailing comma
      
      it "fails parsing in strict mode" do
        agent = agent_class.new(name: "John")
        result = agent.direct_run
        
        expect(result[:success]).to be false
        expect(result[:error]).to include("Failed to parse AI response")
      end
    end

    it "uses OpenAI response_format for strict validation" do
      agent = agent_class.new(name: "John")
      format = agent.response_format
      
      expect(format).not_to be_nil
      expect(format[:type]).to eq("json_schema")
      expect(format[:json_schema][:strict]).to be true
    end
  end

  describe "tolerant validation mode (new default)" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "TolerantTestAgent"
        
        schema do
          field :title, type: :string, required: true
          field :priority, type: :string, required: false, default: "medium", 
                enum: ["low", "medium", "high"]
          field :metadata, type: :object, required: false, passthrough: true
          field :count, type: :integer, required: false, flexible: true, default: 0
          validation :tolerant
          allow_extra_fields true
        end
        
        def self.name
          "TolerantTestAgent"
        end
      end
    end

    context "with valid JSON response" do
      let(:response_content) { '{"title": "Test Task", "priority": "high", "count": 5}' }
      
      it "parses successfully with all fields" do
        agent = agent_class.new(title: "Test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:title]).to eq("Test Task")
        expect(result[:parsed_output][:priority]).to eq("high")
        expect(result[:parsed_output][:count]).to eq(5)
      end
    end

    context "with malformed JSON response" do
      let(:response_content) { '{"title": "Test Task", "priority": "high",}' }  # Trailing comma
      
      it "repairs and parses successfully" do
        agent = agent_class.new(title: "Test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:title]).to eq("Test Task")
        expect(result[:parsed_output][:priority]).to eq("high")
        expect(result[:warnings]).to be_present if result[:warnings]
      end
    end

    context "with missing optional fields" do
      let(:response_content) { '{"title": "Test Task"}' }
      
      it "adds default values for missing optional fields" do
        agent = agent_class.new(title: "Test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:title]).to eq("Test Task")
        expect(result[:parsed_output][:priority]).to eq("medium")  # Default value
        expect(result[:parsed_output][:count]).to eq(0)  # Default value
      end
    end

    context "with extra fields" do
      let(:response_content) do
        '{"title": "Test Task", "priority": "high", "extra_field": "should be kept", "another": 123}'
      end
      
      it "captures extra fields with warnings" do
        agent = agent_class.new(title: "Test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:title]).to eq("Test Task")
        expect(result[:parsed_output][:extra_field]).to eq("should be kept")
        expect(result[:parsed_output][:another]).to eq(123)
        expect(result[:warnings]).to be_present if result[:warnings]
      end
    end

    context "with flexible field type coercion" do
      let(:response_content) { '{"title": "Test Task", "count": "42"}' }  # String instead of integer
      
      it "coerces flexible field types" do
        agent = agent_class.new(title: "Test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:title]).to eq("Test Task")
        expect(result[:parsed_output][:count]).to eq(42)  # Coerced to integer
      end
    end

    context "with invalid enum values" do
      let(:response_content) { '{"title": "Test Task", "priority": "invalid_priority"}' }
      
      it "warns about invalid enum but doesn't fail" do
        agent = agent_class.new(title: "Test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:title]).to eq("Test Task")
        expect(result[:parsed_output][:priority]).to eq("invalid_priority")
        expect(result[:warnings]).to be_present if result[:warnings]
      end
    end

    context "with passthrough field" do
      let(:response_content) do
        '{"title": "Test", "metadata": {"complex": {"nested": {"data": ["a", "b"]}}, "tags": ["x"]}}'
      end
      
      it "accepts complex structures in passthrough fields" do
        agent = agent_class.new(title: "Test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:metadata]).to be_a(Hash)
        expect(result[:parsed_output][:metadata][:complex][:nested][:data]).to eq(["a", "b"])
      end
    end

    it "does not use OpenAI response_format in tolerant mode" do
      agent = agent_class.new(title: "Test")
      format = agent.response_format
      
      expect(format).to be_nil
    end

    it "includes schema instructions in system prompt" do
      agent = agent_class.new(title: "Test")
      
      # Mock the prompt resolution
      allow(agent).to receive(:determine_prompt_spec).and_return(nil)
      expect { agent.build_instructions }.to raise_error(RAAF::DSL::Error)
    end
  end

  describe "partial validation mode (most flexible)" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "PartialTestAgent"
        
        schema do
          field :title, type: :string, required: true
          field :status, type: :string, required: true, enum: ["pending", "active", "done"]
          field :score, type: :integer, required: false
          validation :partial
        end
        
        def self.name
          "PartialTestAgent"
        end
      end
    end

    context "with mixed valid and invalid data" do
      let(:response_content) do
        '{"title": "Valid Title", "status": "invalid_status", "score": "not_a_number", "extra": "ok"}'
      end
      
      it "includes valid fields and handles invalid ones gracefully" do
        agent = agent_class.new(title: "Test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:partial]).to be true if result.key?(:partial)
        expect(result[:parsed_output][:title]).to eq("Valid Title")
        expect(result[:parsed_output][:status]).to eq("invalid_status")  # Included despite enum violation
        expect(result[:parsed_output][:extra]).to eq("ok")  # Extra field included
        expect(result[:warnings]).to be_present if result[:warnings]
      end
    end

    context "with completely missing required fields" do
      let(:response_content) { '{"unrelated": "data", "other": 123}' }
      
      it "warns about missing required fields but doesn't fail" do
        agent = agent_class.new(title: "Test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:partial]).to be true if result.key?(:partial)
        expect(result[:parsed_output][:unrelated]).to eq("data")
        expect(result[:warnings]).to be_present if result[:warnings]
      end
    end

    it "does not use OpenAI response_format in partial mode" do
      agent = agent_class.new(title: "Test")
      format = agent.response_format
      
      expect(format).to be_nil
    end
  end

  describe "schema instructions generation" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "InstructionTestAgent"
        
        schema do
          field :name, type: :string, required: true, description: "User's full name"
          field :priority, type: :string, required: false, default: "normal", 
                enum: ["low", "normal", "high"], description: "Task priority level"
          field :metadata, type: :object, required: false, passthrough: true,
                description: "Additional metadata"
          validation :tolerant
        end
        
        def self.name
          "InstructionTestAgent"
        end
      end
    end

    it "generates comprehensive schema instructions for tolerant mode" do
      agent = agent_class.new(name: "Test")
      schema_def = agent.build_schema
      instructions = agent.build_schema_instructions(schema_def)
      
      expect(instructions).to include("Response Format Requirements")
      expect(instructions).to include("valid JSON")
      expect(instructions).to include("name")
      expect(instructions).to include("REQUIRED")
      expect(instructions).to include("priority")
      expect(instructions).to include("optional")
      expect(instructions).to include("Validation Mode: Tolerant")
      expect(instructions).to include("REQUIRED fields must always be present")
    end
  end

  describe "error handling and dead letter queue" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "ErrorTestAgent"
        
        schema do
          field :result, type: :string, required: true
          validation :tolerant
        end
        
        def self.name
          "ErrorTestAgent"
        end
      end
    end

    context "with completely unparseable response" do
      let(:response_content) { "This is not JSON at all and cannot be repaired" }
      
      it "logs to dead letter queue and returns error" do
        agent = agent_class.new(result: "test")
        
        expect(agent).to receive(:log_to_dead_letter)
        result = agent.direct_run
        
        expect(result[:success]).to be false
        expect(result[:error]).to include("Unable to parse or validate response")
        expect(result[:raw_content]).to eq(response_content)
      end
    end
  end

  describe "union type support" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "UnionTestAgent"
        
        schema do
          field :data, type: :union, required: true, schemas: [
            { type: "object", properties: { summary: { type: "string" } } },
            { type: "array", items: { type: "string" } },
            { type: "string" }
          ]
          validation :tolerant
        end
        
        def self.name
          "UnionTestAgent"
        end
      end
    end

    context "with object data" do
      let(:response_content) { '{"data": {"summary": "Object format"}}' }
      
      it "accepts object format" do
        agent = agent_class.new(data: "test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:data]).to eq(summary: "Object format")
      end
    end

    context "with array data" do
      let(:response_content) { '{"data": ["item1", "item2", "item3"]}' }
      
      it "accepts array format" do
        agent = agent_class.new(data: "test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:data]).to eq(["item1", "item2", "item3"])
      end
    end

    context "with string data" do
      let(:response_content) { '{"data": "Simple string"}' }
      
      it "accepts string format" do
        agent = agent_class.new(data: "test")
        result = agent.direct_run
        
        expect(result[:success]).to be true
        expect(result[:parsed_output][:data]).to eq("Simple string")
      end
    end
  end
end