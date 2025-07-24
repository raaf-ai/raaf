# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Guardrails Integration" do
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  let(:length_guardrail) { RAAF::Guardrails::LengthInputGuardrail.new(max_length: 10) }

  before do
    mock_provider.add_response("Test response")
  end

  describe "Agent-level guardrails" do
    it "triggers input guardrail when added to agent" do
      agent = RAAF::Agent.new(
        name: "TestAgent",
        instructions: "Test agent",
        model: "gpt-4o"
      )
      agent.add_input_guardrail(length_guardrail)

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      # Short input should work
      result = runner.run("short")
      expect(result).to be_a(RAAF::RunResult)

      # Long input should raise error
      expect do
        runner.run("this is a very long input that exceeds the limit")
      end.to raise_error(RAAF::Guardrails::InputGuardrailTripwireTriggered, /Input too long/)
    end
  end

  describe "Run-level guardrails" do
    it "triggers input guardrail when passed to run method" do
      agent = RAAF::Agent.new(
        name: "TestAgent",
        instructions: "Test agent",
        model: "gpt-4o"
      )

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      # Short input should work
      result = runner.run("short", input_guardrails: [length_guardrail])
      expect(result).to be_a(RAAF::RunResult)

      # Long input should raise error
      expect do
        runner.run("this is a very long input that exceeds the limit", input_guardrails: [length_guardrail])
      end.to raise_error(RAAF::Guardrails::InputGuardrailTripwireTriggered, /Input too long/)
    end
  end

  describe "Debugging guardrail execution" do
    it "shows what happens during guardrail execution" do
      agent = RAAF::Agent.new(
        name: "DebugAgent",
        instructions: "Debug agent",
        model: "gpt-4o"
      )
      agent.add_input_guardrail(length_guardrail)

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      # Check the guardrail directly
      long_input = "this is a very long input that exceeds the limit"
      guardrail_result = length_guardrail.run(nil, nil, long_input)
      expect(guardrail_result.tripwire_triggered?).to be true
      expect(guardrail_result.output.output_info[:blocked_reason]).to include("Input too long")

      # This should raise an error
      expect do
        runner.run(long_input)
      end.to raise_error(RAAF::Guardrails::InputGuardrailTripwireTriggered)
    end
  end
end
