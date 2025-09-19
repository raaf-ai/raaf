# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Agent, "basic functionality" do
  let(:context) { RAAF::DSL::ContextVariables.new(test: true) }
  let(:agent) { TestAgents::BasicTestAgent.new(context: context) }

  describe "#initialize" do
    it "accepts context parameter" do
      expect { TestAgents::BasicTestAgent.new(context: context) }.not_to raise_error
    end

    it "accepts context_variables parameter for compatibility" do
      expect { TestAgents::BasicTestAgent.new(context_variables: context) }.not_to raise_error
    end

    it "accepts processing_params" do
      agent = TestAgents::BasicTestAgent.new(context: context, processing_params: { foo: "bar" })
      expect(agent.processing_params).to eq({ foo: "bar" })
    end

    it "defaults to empty context when not provided" do
      agent = TestAgents::BasicTestAgent.new
      expect(agent.context).to be_a(RAAF::DSL::ContextVariables)
      expect(agent.context.to_h).to eq({})
    end
  end

  describe "#agent_name" do
    it "returns the configured agent name" do
      expect(agent.agent_name).to eq("BasicTestAgent")
    end

    it "falls back to class name if not configured" do
      minimal = TestAgents::MinimalAgent.new
      expect(minimal.agent_name).to eq("MinimalAgent")
    end
  end

  describe "#model_name" do
    it "returns the configured model" do
      expect(agent.model_name).to eq("gpt-4o")
    end

    it "defaults to gpt-4o if not configured" do
      minimal = TestAgents::MinimalAgent.new
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
      minimal = TestAgents::MinimalAgent.new
      expect(minimal.build_schema).to be_nil
    end
  end

  describe "#response_format" do
    it "returns structured format with schema" do
      format = agent.response_format
      expect(format[:type]).to eq("json_schema")
      expect(format[:json_schema][:strict]).to eq(true)
      # Compare schemas by converting to JSON and back to normalize keys
      expected_schema = agent.build_schema
      actual_schema = format[:json_schema][:schema]

      # Convert both to JSON strings for comparison to handle mixed key types
      expected_json = JSON.generate(expected_schema)
      actual_json = JSON.generate(actual_schema)
      expect(actual_json).to eq(expected_json)
    end

    it "returns nil for unstructured output" do
      minimal = TestAgents::MinimalAgent.new
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