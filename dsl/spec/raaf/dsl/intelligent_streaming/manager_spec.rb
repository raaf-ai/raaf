# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/intelligent_streaming"

RSpec.describe RAAF::DSL::IntelligentStreaming::Manager do
  let(:manager) { described_class.new }

  # Mock agent classes
  let(:trigger_agent) do
    Class.new do
      def self.name
        "TriggerAgent"
      end

      def self.streaming_trigger?
        true
      end

      def self.streaming_config
        @streaming_config ||= RAAF::DSL::IntelligentStreaming::Config.new(
          stream_size: 100,
          over: :items
        )
      end
    end
  end

  let(:normal_agent) do
    Class.new do
      def self.name
        "NormalAgent"
      end

      def self.streaming_trigger?
        false
      end
    end
  end

  let(:another_trigger) do
    Class.new do
      def self.name
        "AnotherTrigger"
      end

      def self.streaming_trigger?
        true
      end

      def self.streaming_config
        @streaming_config ||= RAAF::DSL::IntelligentStreaming::Config.new(
          stream_size: 50,
          over: :companies
        )
      end
    end
  end

  describe "#detect_scopes" do
    context "with a simple linear flow" do
      it "detects a single scope" do
        flow = [trigger_agent, normal_agent, normal_agent]
        scopes = manager.detect_scopes(flow)

        expect(scopes.size).to eq(1)
        expect(scopes.first.trigger_agent).to eq(trigger_agent)
        expect(scopes.first.scope_agents).to eq([normal_agent, normal_agent])
        expect(scopes.first.stream_size).to eq(100)
        expect(scopes.first.array_field).to eq(:items)
      end

      it "detects no scopes when no streaming agents" do
        flow = [normal_agent, normal_agent]
        scopes = manager.detect_scopes(flow)

        expect(scopes).to be_empty
      end

      it "detects multiple scopes" do
        flow = [trigger_agent, normal_agent, another_trigger, normal_agent]
        scopes = manager.detect_scopes(flow)

        expect(scopes.size).to eq(2)

        # First scope
        expect(scopes[0].trigger_agent).to eq(trigger_agent)
        expect(scopes[0].scope_agents).to eq([normal_agent])
        expect(scopes[0].stream_size).to eq(100)

        # Second scope
        expect(scopes[1].trigger_agent).to eq(another_trigger)
        expect(scopes[1].scope_agents).to eq([normal_agent])
        expect(scopes[1].stream_size).to eq(50)
      end

      it "handles adjacent trigger agents" do
        flow = [trigger_agent, another_trigger, normal_agent]
        scopes = manager.detect_scopes(flow)

        expect(scopes.size).to eq(2)

        # First scope has no agents
        expect(scopes[0].trigger_agent).to eq(trigger_agent)
        expect(scopes[0].scope_agents).to eq([])

        # Second scope has the normal agent
        expect(scopes[1].trigger_agent).to eq(another_trigger)
        expect(scopes[1].scope_agents).to eq([normal_agent])
      end
    end

    context "with nested flow structures" do
      # Mock ChainedAgent structure
      let(:chained_flow) do
        double("ChainedAgent",
          first_agent: trigger_agent,
          second_agent: normal_agent
        )
      end

      it "flattens and detects scopes from chained agents" do
        scopes = manager.detect_scopes(chained_flow)

        expect(scopes.size).to eq(1)
        expect(scopes.first.trigger_agent).to eq(trigger_agent)
        expect(scopes.first.scope_agents).to eq([normal_agent])
      end
    end
  end

  describe "#flatten_flow_chain" do
    it "returns array for single agent" do
      result = manager.flatten_flow_chain(trigger_agent)
      expect(result).to eq([trigger_agent])
    end

    it "flattens array of agents" do
      flow = [trigger_agent, normal_agent, another_trigger]
      result = manager.flatten_flow_chain(flow)
      expect(result).to eq([trigger_agent, normal_agent, another_trigger])
    end

    it "recursively flattens nested arrays" do
      flow = [trigger_agent, [normal_agent, another_trigger]]
      result = manager.flatten_flow_chain(flow)
      expect(result).to eq([trigger_agent, normal_agent, another_trigger])
    end

    it "handles objects with to_a method" do
      flow = double("ArrayLike", to_a: [trigger_agent, normal_agent])
      result = manager.flatten_flow_chain(flow)
      expect(result).to eq([trigger_agent, normal_agent])
    end

    it "handles objects with agents method" do
      flow = double("AgentContainer", agents: [trigger_agent, normal_agent])
      result = manager.flatten_flow_chain(flow)
      expect(result).to eq([trigger_agent, normal_agent])
    end

    it "handles ChainedAgent structure" do
      flow = double("ChainedAgent",
        first_agent: trigger_agent,
        second_agent: normal_agent
      )
      result = manager.flatten_flow_chain(flow)
      expect(result).to eq([trigger_agent, normal_agent])
    end

    it "handles deeply nested structures" do
      nested = double("Nested",
        first_agent: [trigger_agent],
        second_agent: double("Inner", to_a: [normal_agent, another_trigger])
      )
      result = manager.flatten_flow_chain(nested)
      expect(result).to eq([trigger_agent, normal_agent, another_trigger])
    end
  end

  describe "#validate_scopes!" do
    it "validates valid scopes without error" do
      scope = RAAF::DSL::IntelligentStreaming::Scope.new(
        trigger_agent: trigger_agent,
        scope_agents: [normal_agent],
        stream_size: 100
      )

      expect { manager.validate_scopes!([scope]) }.not_to raise_error
    end

    it "raises error for invalid scope" do
      invalid_scope = RAAF::DSL::IntelligentStreaming::Scope.new(
        trigger_agent: nil,
        scope_agents: [],
        stream_size: 100
      )

      expect {
        manager.validate_scopes!([invalid_scope])
      }.to raise_error(RAAF::DSL::IntelligentStreaming::Manager::ConfigurationError, /Invalid streaming scope/)
    end

    it "validates multiple scopes" do
      scope1 = RAAF::DSL::IntelligentStreaming::Scope.new(
        trigger_agent: trigger_agent,
        scope_agents: [],
        stream_size: 100
      )
      scope2 = RAAF::DSL::IntelligentStreaming::Scope.new(
        trigger_agent: another_trigger,
        scope_agents: [normal_agent],
        stream_size: 50
      )

      expect { manager.validate_scopes!([scope1, scope2]) }.not_to raise_error
    end
  end
end