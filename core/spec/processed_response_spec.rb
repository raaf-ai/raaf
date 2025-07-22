# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/processed_response"

RSpec.describe RAAF::ProcessedResponse do
  let(:processed_response) do
    described_class.new(
      new_items: [{ type: "message" }],
      handoffs: [],
      functions: [double("ToolRun")],
      computer_actions: [],
      local_shell_calls: [],
      tools_used: ["get_weather"]
    )
  end

  it "categorizes response elements correctly" do
    expect(processed_response.tool_usage?).to be(true)
    expect(processed_response.handoffs_detected?).to be(false)
    expect(processed_response.tools_or_actions_to_run?).to be(true)
    expect(processed_response.tools_used).to eq(["get_weather"])
  end

  it "handles multiple handoffs" do
    handoff1 = double("Handoff1")
    handoff2 = double("Handoff2")

    multi_handoff_response = described_class.new(
      new_items: [],
      handoffs: [handoff1, handoff2],
      functions: [],
      computer_actions: [],
      local_shell_calls: [],
      tools_used: []
    )

    expect(multi_handoff_response.primary_handoff).to eq(handoff1)
    expect(multi_handoff_response.rejected_handoffs).to eq([handoff2])
  end
end