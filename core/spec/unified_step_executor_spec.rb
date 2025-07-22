# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/step_result"
require_relative "../lib/raaf/unified_step_executor"

RSpec.describe RAAF::UnifiedStepExecutor do
  let(:runner) { double("Runner") }
  let(:executor) { described_class.new(runner: runner) }

  describe "#to_runner_format" do
    it "converts StepResult to runner format" do
      step_result = RAAF::StepResult.new(
        original_input: "Hello",
        model_response: {},
        pre_step_items: [],
        new_step_items: [{ type: "message", content: "Response" }],
        next_step: RAAF::NextStepFinalOutput.new("Final")
      )

      runner_format = executor.to_runner_format(step_result)

      expect(runner_format).to include(
        done: true,
        handoff: nil,
        generated_items: [{ type: "message", content: "Response" }],
        final_output: "Final",
        should_continue: false
      )
    end

    it "handles handoff results in runner format" do
      target_agent = double("Agent", name: "TargetAgent")
      handoff_result = RAAF::StepResult.new(
        original_input: "Hello",
        model_response: {},
        pre_step_items: [],
        new_step_items: [],
        next_step: RAAF::NextStepHandoff.new(target_agent)
      )

      runner_format = executor.to_runner_format(handoff_result)

      expect(runner_format[:handoff]).to eq({ assistant: "TargetAgent" })
      expect(runner_format[:done]).to be(false)
    end
  end
end