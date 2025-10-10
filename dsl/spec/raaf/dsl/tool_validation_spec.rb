# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::DSL::Agent Tool Parameter Validation" do
  # Test tool class that provides tool_definition
  class TestToolWithDefinition
    def tool_name
      "test_tool"
    end

    def tool_definition
      {
        type: "function",
        function: {
          name: "test_tool",
          description: "Test tool for validation",
          parameters: {
            type: "object",
            properties: {
              query: { type: "string", description: "Search query" },
              limit: { type: "integer", description: "Result limit" },
              tags: { type: "array", description: "Filter tags" },
              options: { type: "object", description: "Additional options" }
            },
            required: %w[query limit],
            additionalProperties: false
          }
        }
      }
    end

    def call(query:, limit:, tags: [], options: {})
      { success: true, query: query, limit: limit, tags: tags, options: options }
    end
  end

  # Agent class for testing validation
  class TestValidationAgent < RAAF::DSL::Agent
    agent_name "TestValidationAgent"
    model "gpt-4o"
    static_instructions "Test agent for validation"
  end

  let(:agent) { TestValidationAgent.new }
  let(:tool) { TestToolWithDefinition.new }

  describe "parameter validation" do
    context "when validation is enabled" do
      before do
        # Enable validation for this agent class
        TestValidationAgent.tool_execution do
          enable_validation true
          enable_logging false
          enable_metadata false
        end
      end

      context "with missing required parameters" do
        it "raises ArgumentError for missing 'query' parameter" do
          expect {
            agent.send(:validate_tool_arguments, tool, { limit: 10 })
          }.to raise_error(ArgumentError, /Missing required parameter: query/)
        end

        it "raises ArgumentError for missing 'limit' parameter" do
          expect {
            agent.send(:validate_tool_arguments, tool, { query: "test" })
          }.to raise_error(ArgumentError, /Missing required parameter: limit/)
        end

        it "raises ArgumentError when all required parameters are missing" do
          expect {
            agent.send(:validate_tool_arguments, tool, {})
          }.to raise_error(ArgumentError, /Missing required parameter/)
        end
      end

      context "with incorrect parameter types" do
        it "raises ArgumentError when query is not a string" do
          expect {
            agent.send(:validate_tool_arguments, tool, { query: 123, limit: 10 })
          }.to raise_error(ArgumentError, /Parameter query must be a string/)
        end

        it "raises ArgumentError when limit is not an integer" do
          expect {
            agent.send(:validate_tool_arguments, tool, { query: "test", limit: "10" })
          }.to raise_error(ArgumentError, /Parameter limit must be an integer/)
        end

        it "raises ArgumentError when tags is not an array" do
          expect {
            agent.send(:validate_tool_arguments, tool, { query: "test", limit: 10, tags: "tag1" })
          }.to raise_error(ArgumentError, /Parameter tags must be an array/)
        end
      end

      context "with correct parameters" do
        it "does not raise error with all required parameters" do
          expect {
            agent.send(:validate_tool_arguments, tool, { query: "test", limit: 10 })
          }.not_to raise_error
        end

        it "does not raise error with optional parameters included" do
          expect {
            agent.send(:validate_tool_arguments, tool, {
              query: "test",
              limit: 10,
              tags: %w[ruby rails],
              options: { verbose: true }
            })
          }.not_to raise_error
        end

        it "accepts parameters with symbol keys" do
          expect {
            agent.send(:validate_tool_arguments, tool, { query: "test", limit: 10 })
          }.not_to raise_error
        end

        it "accepts parameters with string keys" do
          expect {
            agent.send(:validate_tool_arguments, tool, { "query" => "test", "limit" => 10 })
          }.not_to raise_error
        end
      end

      context "with tools lacking tool_definition" do
        let(:simple_tool) do
          double("simple_tool", tool_name: "simple")
        end

        it "does not raise error when tool has no tool_definition method" do
          expect {
            agent.send(:validate_tool_arguments, simple_tool, { any_param: "value" })
          }.not_to raise_error
        end
      end
    end

    context "when validation is disabled" do
      before do
        # Disable validation for this agent class
        TestValidationAgent.tool_execution do
          enable_validation false
          enable_logging false
          enable_metadata false
        end
      end

      it "does not call validation when validation is disabled" do
        # Mock the validation method to ensure it's not called
        allow(agent).to receive(:validate_tool_arguments).and_call_original

        # Call perform_pre_execution which should skip validation
        agent.send(:perform_pre_execution, tool, {})

        # Verify validate_tool_arguments was not called
        expect(agent).not_to have_received(:validate_tool_arguments)
      end

      it "skips type validation when validation is disabled" do
        # Mock the validation method to ensure it's not called
        allow(agent).to receive(:validate_tool_arguments).and_call_original

        # Call perform_pre_execution with wrong types
        agent.send(:perform_pre_execution, tool, { query: 123, limit: "wrong" })

        # Verify validate_tool_arguments was not called
        expect(agent).not_to have_received(:validate_tool_arguments)
      end
    end
  end

  describe "error messages" do
    before do
      TestValidationAgent.tool_execution do
        enable_validation true
      end
    end

    it "provides descriptive error for missing required parameter" do
      expect {
        agent.send(:validate_tool_arguments, tool, { limit: 10 })
      }.to raise_error(ArgumentError) do |error|
        expect(error.message).to include("Missing required parameter")
        expect(error.message).to include("query")
      end
    end

    it "provides descriptive error for incorrect type" do
      expect {
        agent.send(:validate_tool_arguments, tool, { query: 123, limit: 10 })
      }.to raise_error(ArgumentError) do |error|
        expect(error.message).to include("Parameter query must be a string")
      end
    end
  end

  describe "validation configuration query method" do
    it "returns true when validation is enabled" do
      TestValidationAgent.tool_execution do
        enable_validation true
      end

      expect(agent.validation_enabled?).to be true
    end

    it "returns false when validation is disabled" do
      TestValidationAgent.tool_execution do
        enable_validation false
      end

      expect(agent.validation_enabled?).to be false
    end
  end
end
