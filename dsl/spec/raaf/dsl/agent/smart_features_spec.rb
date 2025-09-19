# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Agent, "smart features" do
  let(:valid_context) { RAAF::DSL::ContextVariables.new(api_key: "sk-123456", endpoint: "https://api.example.com") }
  let(:invalid_context) { RAAF::DSL::ContextVariables.new(endpoint: "https://api.example.com") }

  describe "Context Validation" do
    it "validates required context keys", pending: "Context validation not fully implemented" do
      expect { TestAgents::SmartTestAgent.new(context: invalid_context) }
        .to raise_error(ArgumentError, /Required context keys missing: api_key/)
    end

    it "validates context value types", pending: "Context validation not fully implemented" do
      invalid = RAAF::DSL::ContextVariables.new(api_key: 123, endpoint: "test")
      expect { TestAgents::SmartTestAgent.new(context: invalid) }
        .to raise_error(ArgumentError, /Context key 'api_key' must be String/)
    end

    it "accepts valid context" do
      expect { TestAgents::SmartTestAgent.new(context: valid_context) }.not_to raise_error
    end
  end

  describe "DSL Configuration" do
    let(:agent) { TestAgents::SmartTestAgent.new(context: valid_context) }

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
      expect(TestAgents::SmartTestAgent._retry_config).to include(:rate_limit)
      expect(TestAgents::SmartTestAgent._retry_config[:rate_limit]).to include(
        max_attempts: 3,
        backoff: :exponential
      )
    end

    it "has circuit breaker configuration" do
      expect(TestAgents::SmartTestAgent._circuit_breaker_config).to include(
        threshold: 5,
        timeout: 60,
        reset_timeout: 300
      )
    end
  end

  describe "Schema DSL" do
    let(:agent) { TestAgents::SmartTestAgent.new(context: valid_context) }

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
    let(:agent) { TestAgents::SmartTestAgent.new(context: valid_context) }

    it "builds system prompt from string" do
      expect(agent.build_instructions).to eq("You are a smart test assistant.")
    end

    it "builds user prompt from block" do
      prompt = agent.build_user_prompt
      expect(prompt).to eq("Process endpoint https://api.example.com with key sk-123...")
    end
  end

  describe "#run with smart features" do
    let(:agent) { TestAgents::SmartTestAgent.new(context: valid_context) }

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
    let(:agent) { TestAgents::SmartTestAgent.new(context: valid_context) }

    it "delegates to run method" do
      expect(agent).to receive(:run).and_return({ success: true })
      result = agent.call
      expect(result).to eq({ success: true })
    end
  end

  describe "Error Handling" do
    let(:agent) { TestAgents::SmartTestAgent.new(context: valid_context) }

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