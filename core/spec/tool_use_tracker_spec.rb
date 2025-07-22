# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/tool_use_tracker"

RSpec.describe RAAF::ToolUseTracker do
  let(:tracker) { described_class.new }
  let(:agent) { double("Agent", name: "TestAgent") }

  it "tracks tool usage for agents" do
    expect(tracker.used_tools?(agent)).to be(false)

    tracker.add_tool_use(agent, %w[get_weather send_email])

    expect(tracker.used_tools?(agent)).to be(true)
    expect(tracker.tools_used_by(agent)).to eq(%w[get_weather send_email])
    expect(tracker.total_tool_usage_count).to eq(2)
  end

  it "handles duplicate tool names" do
    tracker.add_tool_use(agent, ["get_weather"])
    tracker.add_tool_use(agent, %w[get_weather send_email])

    expect(tracker.tools_used_by(agent)).to eq(%w[get_weather send_email])
    expect(tracker.total_tool_usage_count).to eq(2)
  end

  it "provides usage summary" do
    agent1 = double("Agent1", name: "Agent1")
    agent2 = double("Agent2", name: "Agent2")

    tracker.add_tool_use(agent1, ["tool1"])
    tracker.add_tool_use(agent2, %w[tool2 tool3])

    summary = tracker.usage_summary
    expect(summary).to eq("Agent1" => ["tool1"], "Agent2" => %w[tool2 tool3])
  end
end