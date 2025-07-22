# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/step_result"

RSpec.describe RAAF::StepResult do
  let(:step_result) do
    described_class.new(
      original_input: "Hello",
      model_response: { content: "Hi there" },
      pre_step_items: [{ type: "message", content: "Previous" }],
      new_step_items: [{ type: "message", content: "Current" }],
      next_step: RAAF::NextStepRunAgain.new
    )
  end

  it "creates immutable step results" do
    expect(step_result.original_input).to eq("Hello")
    expect(step_result.generated_items.size).to eq(2)
    expect(step_result.should_continue?).to be(true)
    expect(step_result.final_output?).to be(false)
    expect(step_result.handoff_occurred?).to be(false)
  end

  it "handles final output results" do
    final_result = described_class.new(
      original_input: "Hello",
      model_response: {},
      pre_step_items: [],
      new_step_items: [],
      next_step: RAAF::NextStepFinalOutput.new("Final answer")
    )

    expect(final_result.final_output?).to be(true)
    expect(final_result.final_output).to eq("Final answer")
  end

  it "handles handoff results" do
    target_agent = double("Agent", name: "TargetAgent")
    handoff_result = described_class.new(
      original_input: "Hello",
      model_response: {},
      pre_step_items: [],
      new_step_items: [],
      next_step: RAAF::NextStepHandoff.new(target_agent)
    )

    expect(handoff_result.handoff_occurred?).to be(true)
    expect(handoff_result.handoff_agent).to eq(target_agent)
  end
end