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
      expect {
        runner.run("this is a very long input that exceeds the limit")
      }.to raise_error(RAAF::Guardrails::InputGuardrailTripwireTriggered, /Input too long/)
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
      expect {
        runner.run("this is a very long input that exceeds the limit", input_guardrails: [length_guardrail])
      }.to raise_error(RAAF::Guardrails::InputGuardrailTripwireTriggered, /Input too long/)
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

      # Check that agent has guardrails
      puts "Agent has guardrails: #{agent.input_guardrails?}"
      puts "Number of guardrails: #{agent.input_guardrails.length}"

      # Check the guardrail directly
      long_input = "this is a very long input that exceeds the limit"
      guardrail_result = length_guardrail.run(nil, nil, long_input)
      puts "Guardrail result: #{guardrail_result.tripwire_triggered?}"
      puts "Guardrail message: #{guardrail_result.output.output_info}"

      # This should raise an error
      expect {
        runner.run(long_input)
      }.to raise_error(RAAF::Guardrails::InputGuardrailTripwireTriggered)
    end
  end
end