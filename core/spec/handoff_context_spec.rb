# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::HandoffContext do
  let(:current_agent) { "Agent1" }
  let(:handoff_context) { described_class.new(current_agent: current_agent) }

  describe "#initialize" do
    it "sets current agent" do
      expect(handoff_context.current_agent).to eq(current_agent)
    end

    it "initializes with default values" do
      expect(handoff_context.target_agent).to be_nil
      expect(handoff_context.handoff_data).to eq({})
      expect(handoff_context.shared_context).to eq({})
      expect(handoff_context.handoff_timestamp).to be_nil
    end

    it "works without current_agent parameter" do
      context = described_class.new
      expect(context.current_agent).to be_nil
    end
  end

  describe "#set_handoff" do
    let(:target_agent) { "Agent2" }
    let(:handoff_data) { { task: "process data", priority: "high" } }
    let(:reason) { "Need specialized processing" }

    it "sets handoff parameters" do
      result = handoff_context.set_handoff(
        target_agent: target_agent,
        data: handoff_data,
        reason: reason
      )

      expect(result).to be true
      expect(handoff_context.target_agent).to eq(target_agent)
      expect(handoff_context.handoff_data).to eq(handoff_data)
      expect(handoff_context.handoff_timestamp).to be_a(Time)
    end

    it "merges data into shared context" do
      handoff_context.set_handoff(
        target_agent: target_agent,
        data: handoff_data
      )

      expect(handoff_context.shared_context).to include(handoff_data)
    end

    it "duplicates data to prevent external modification" do
      original_data = { task: "process data" }
      handoff_context.set_handoff(
        target_agent: target_agent,
        data: original_data
      )

      original_data[:task] = "modified"
      expect(handoff_context.handoff_data[:task]).to eq("process data")
    end

    it "works without reason" do
      result = handoff_context.set_handoff(
        target_agent: target_agent,
        data: handoff_data
      )

      expect(result).to be true
    end

    it "logs handoff preparation" do
      expect(handoff_context).to receive(:log_info).with(
        "Handoff prepared",
        from: current_agent,
        to: target_agent,
        reason: reason,
        data_keys: handoff_data.keys
      )

      handoff_context.set_handoff(
        target_agent: target_agent,
        data: handoff_data,
        reason: reason
      )
    end
  end

  describe "#execute_handoff" do
    let(:target_agent) { "Agent2" }

    context "when no target agent is set" do
      it "returns error" do
        result = handoff_context.execute_handoff

        expect(result[:success]).to be false
        expect(result[:error]).to eq("No target agent set")
      end
    end

    context "when target agent is set" do
      before do
        handoff_context.set_handoff(
          target_agent: target_agent,
          data: { task: "test" }
        )
      end

      it "executes handoff successfully" do
        result = handoff_context.execute_handoff

        expect(result[:success]).to be true
        expect(result[:previous_agent]).to eq(current_agent)
        expect(result[:current_agent]).to eq(target_agent)
        expect(result[:handoff_data]).to include(task: "test")
        expect(result[:timestamp]).to be_a(Time)
      end

      it "updates current agent" do
        handoff_context.execute_handoff

        expect(handoff_context.current_agent).to eq(target_agent)
        expect(handoff_context.target_agent).to be_nil
      end

      it "adds handoff to chain" do
        expect(handoff_context).to receive(:add_handoff).with(current_agent, target_agent)

        handoff_context.execute_handoff
      end

      it "logs handoff execution" do
        expect(handoff_context).to receive(:log_info).with(
          "Handoff executed",
          from: current_agent,
          to: target_agent,
          timestamp: be_a(Time)
        )

        handoff_context.execute_handoff
      end
    end

    context "when circular handoff is detected" do
      before do
        handoff_context.set_handoff(target_agent: target_agent, data: {})
        allow(handoff_context).to receive(:handoff_chain).and_return([target_agent])
      end

      it "returns error for circular handoff" do
        result = handoff_context.execute_handoff

        expect(result[:success]).to be false
        expect(result[:error]).to include("Circular handoff detected")
        expect(result[:error]).to include(target_agent)
      end
    end
  end

  describe "#handoff_pending?" do
    it "returns false when no target agent" do
      expect(handoff_context.handoff_pending?).to be false
    end

    it "returns true when target agent is set" do
      handoff_context.set_handoff(target_agent: "Agent2", data: {})

      expect(handoff_context.handoff_pending?).to be true
    end
  end

  describe "#clear_handoff" do
    before do
      handoff_context.set_handoff(
        target_agent: "Agent2",
        data: { task: "test" }
      )
    end

    it "clears handoff state" do
      handoff_context.clear_handoff

      expect(handoff_context.target_agent).to be_nil
      expect(handoff_context.handoff_data).to eq({})
      expect(handoff_context.handoff_timestamp).to be_nil
    end
  end

  describe "#get_handoff_data" do
    let(:handoff_data) { { task: "test", "priority" => "high" } }

    before do
      handoff_context.set_handoff(target_agent: "Agent2", data: handoff_data)
    end

    it "returns all handoff data when no key specified" do
      expect(handoff_context.get_handoff_data).to eq(handoff_data)
    end

    it "returns specific value for string key" do
      expect(handoff_context.get_handoff_data("priority")).to eq("high")
    end

    it "returns specific value for symbol key" do
      expect(handoff_context.get_handoff_data(:task)).to eq("test")
    end

    it "returns nil for non-existent key" do
      expect(handoff_context.get_handoff_data(:nonexistent)).to be_nil
    end
  end

  describe "#build_handoff_message" do
    context "when no handoff data" do
      it "returns empty string" do
        expect(handoff_context.build_handoff_message).to eq("")
      end
    end

    context "when handoff data exists" do
      let(:handoff_data) { { task: "process", priority: "high", items: %w[a b] } }

      before do
        handoff_context.set_handoff(target_agent: "Agent2", data: handoff_data)
      end

      it "builds formatted handoff message" do
        message = handoff_context.build_handoff_message

        expect(message).to include("HANDOFF RECEIVED FROM #{current_agent.upcase}")
        expect(message).to include("TIMESTAMP:")
        expect(message).to include("TASK: process")
        expect(message).to include("PRIORITY: high")
      end

      it "formats different value types correctly" do
        allow(handoff_context).to receive(:format_handoff_value).and_call_original

        handoff_context.build_handoff_message

        expect(handoff_context).to have_received(:format_handoff_value).with("process")
        expect(handoff_context).to have_received(:format_handoff_value).with("high")
        expect(handoff_context).to have_received(:format_handoff_value).with(%w[a b])
      end
    end
  end

  describe "#handoff_chain" do
    it "initializes empty chain" do
      expect(handoff_context.handoff_chain).to eq([])
    end

    it "persists chain between calls" do
      chain = handoff_context.handoff_chain
      chain << "Agent1"

      expect(handoff_context.handoff_chain).to eq(["Agent1"])
    end
  end

  describe "#add_handoff" do
    it "adds handoff to chain" do
      result = handoff_context.add_handoff("Agent1", "Agent2")

      expect(result).to be true
      expect(handoff_context.handoff_chain).to include("Agent1")
    end

    it "limits chain length to 10" do
      15.times { |i| handoff_context.add_handoff("Agent#{i}", "Agent#{i + 1}") }

      expect(handoff_context.handoff_chain.length).to eq(10)
    end

    it "removes oldest entries when chain exceeds limit" do
      15.times { |i| handoff_context.add_handoff("Agent#{i}", "Agent#{i + 1}") }

      expect(handoff_context.handoff_chain).not_to include("Agent0")
      expect(handoff_context.handoff_chain).to include("Agent14")
    end
  end

  describe "#format_handoff_value" do
    it "formats arrays" do
      value = ["item1", "item2", { key: "value" }]
      result = handoff_context.send(:format_handoff_value, value)

      expect(result).to eq('item1, item2, {"key":"value"}')
    end

    it "formats hashes as JSON" do
      value = { key: "value", nested: { inner: "data" } }
      result = handoff_context.send(:format_handoff_value, value)

      expect(result).to eq('{"key":"value","nested":{"inner":"data"}}')
    end

    it "formats other values as strings" do
      expect(handoff_context.send(:format_handoff_value, 123)).to eq("123")
      expect(handoff_context.send(:format_handoff_value, true)).to eq("true")
      expect(handoff_context.send(:format_handoff_value, "string")).to eq("string")
    end
  end

  describe "Logger integration" do
    it "includes Logger module" do
      expect(described_class.included_modules).to include(RAAF::Logger)
    end

    it "has access to logging methods" do
      expect(handoff_context).to respond_to(:log_info)
    end
  end
end
