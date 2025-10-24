# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/intelligent_streaming/scope"

RSpec.describe RAAF::DSL::IntelligentStreaming::Scope do
  # Mock agent classes for testing
  let(:trigger_agent) { double("TriggerAgent", name: "TriggerAgent") }
  let(:agent1) { double("Agent1", name: "Agent1") }
  let(:agent2) { double("Agent2", name: "Agent2") }

  describe "#initialize" do
    it "creates a scope with trigger and scope agents" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [agent1, agent2],
        stream_size: 100,
        array_field: :items
      )

      expect(scope.trigger_agent).to eq(trigger_agent)
      expect(scope.scope_agents).to eq([agent1, agent2])
      expect(scope.stream_size).to eq(100)
      expect(scope.array_field).to eq(:items)
    end

    it "creates a scope without array_field" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [agent1],
        stream_size: 50
      )

      expect(scope.array_field).to be_nil
    end

    it "handles empty scope_agents" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [],
        stream_size: 100
      )

      expect(scope.scope_agents).to eq([])
    end

    it "handles nil scope_agents" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: nil,
        stream_size: 100
      )

      expect(scope.scope_agents).to eq([])
    end
  end

  describe "#valid?" do
    it "returns true for valid scope" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [agent1],
        stream_size: 100
      )

      expect(scope.valid?).to be(true)
    end

    it "returns false without trigger_agent" do
      scope = described_class.new(
        trigger_agent: nil,
        scope_agents: [agent1],
        stream_size: 100
      )

      expect(scope.valid?).to be(false)
    end

    it "returns false without stream_size" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [agent1],
        stream_size: nil
      )

      expect(scope.valid?).to be(false)
    end

    it "returns false with zero stream_size" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [agent1],
        stream_size: 0
      )

      expect(scope.valid?).to be(false)
    end

    it "returns false with negative stream_size" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [agent1],
        stream_size: -10
      )

      expect(scope.valid?).to be(false)
    end
  end

  describe "#includes_agent?" do
    let(:scope) do
      described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [agent1, agent2],
        stream_size: 100
      )
    end

    it "returns true for the trigger agent" do
      expect(scope.includes_agent?(trigger_agent)).to be(true)
    end

    it "returns true for agents in scope_agents" do
      expect(scope.includes_agent?(agent1)).to be(true)
      expect(scope.includes_agent?(agent2)).to be(true)
    end

    it "returns false for agents not in scope" do
      other_agent = double("OtherAgent")
      expect(scope.includes_agent?(other_agent)).to be(false)
    end
  end

  describe "#all_agents" do
    it "returns trigger agent plus scope agents" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [agent1, agent2],
        stream_size: 100
      )

      expect(scope.all_agents).to eq([trigger_agent, agent1, agent2])
    end

    it "returns only trigger agent when scope_agents is empty" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [],
        stream_size: 100
      )

      expect(scope.all_agents).to eq([trigger_agent])
    end
  end

  describe "#to_h" do
    it "converts scope to hash representation" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [agent1, agent2],
        stream_size: 100,
        array_field: :companies
      )

      hash = scope.to_h

      expect(hash).to eq({
        trigger_agent: "TriggerAgent",
        scope_agents: ["Agent1", "Agent2"],
        stream_size: 100,
        array_field: :companies
      })
    end

    it "handles nil array_field" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        scope_agents: [],
        stream_size: 50
      )

      hash = scope.to_h

      expect(hash).to eq({
        trigger_agent: "TriggerAgent",
        scope_agents: [],
        stream_size: 50,
        array_field: nil
      })
    end
  end
end