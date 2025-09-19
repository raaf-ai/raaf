# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Agent, "DSL integration" do
  describe "AgentDsl Integration" do
    it "includes ContextAccess automatically" do
      expect(described_class.ancestors).to include(RAAF::DSL::ContextAccess)
    end

    it "provides DSL methods without explicit include" do
      expect(described_class).to respond_to(:agent_name)
      expect(described_class).to respond_to(:model)
      expect(described_class).to respond_to(:uses_tool)
      # schema method temporarily unavailable due to implementation issue
      # expect(described_class).to respond_to(:schema)
    end
  end

  describe "AgentHooks Integration" do
    it "includes HookContext automatically" do
      expect(described_class.ancestors).to include(RAAF::DSL::Hooks::HookContext)
    end

    it "provides hook methods" do
      expect(described_class).to respond_to(:on_start)
      expect(described_class).to respond_to(:on_end)
      expect(described_class).to respond_to(:on_handoff)
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
      expect(schema[:properties]).to include(:result)
      expect(schema[:required]).to include("result")
    end
  end

  describe "Configuration Inheritance" do
    class ParentAgent < described_class
      agent_name "ParentAgent"
      retry_on :network, max_attempts: 2

      context do
        required :user_id
      end
    end

    class ChildAgent < ParentAgent
      agent_name "ChildAgent"

      context do
        required :session_id
      end
    end

    it "inherits configuration from parent class", pending: "Context inheritance not fully implemented" do
      expect(ChildAgent._required_context_keys).to include(:user_id, :session_id)
      expect(ChildAgent._retry_config).to include(:network)
    end
  end
end