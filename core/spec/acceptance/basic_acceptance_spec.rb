# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF Basic Acceptance", :acceptance do
  # Skip all tests if no API key is available
  before(:context) do
    skip "Acceptance tests require OPENAI_API_KEY to be set" unless ENV["OPENAI_API_KEY"] && !ENV["OPENAI_API_KEY"].empty?
  end

  # Disable VCR for acceptance tests - we want real API calls
  before do
    VCR.turn_off! if defined?(VCR)
  end

  after do
    VCR.turn_on! if defined?(VCR)
  end

  let(:agent) do
    RAAF::Agent.new(
      name: "AcceptanceTestAgent",
      instructions: "You are a helpful assistant for acceptance testing. Keep responses brief.",
      model: "gpt-4o-mini" # Use smaller model for acceptance tests
    )
  end

  describe "Basic agent functionality" do
    it "creates an agent and handles simple conversation" do
      runner = RAAF::Runner.new(agent: agent)

      result = runner.run("Say 'Hello acceptance test' exactly")

      expect(result).not_to be_nil
      expect(result.messages).to be_an(Array)
      expect(result.messages.last[:role]).to eq("assistant")
      expect(result.messages.last[:content].downcase).to include("hello acceptance test")
    end

    it "handles tool calls correctly" do
      tool_called = false
      tool_input = nil

      # Define a simple tool
      define_singleton_method(:acceptance_test_tool) do |input:|
        tool_called = true
        tool_input = input
        "Tool received: #{input}"
      end

      agent.add_tool(method(:acceptance_test_tool))
      runner = RAAF::Runner.new(agent: agent)

      result = runner.run("Please use the acceptance_test_tool with input 'test data'")

      expect(result).not_to be_nil
      expect(tool_called).to be true
      expect(tool_input).to eq("test data")

      # Check that tool response is in messages
      tool_messages = result.messages.select { |m| m[:role] == "tool" }
      expect(tool_messages).not_to be_empty
      expect(tool_messages.first[:content]).to eq("Tool received: test data")
    end
  end

  describe "Multi-agent handoffs" do
    let(:secondary_agent) do
      RAAF::Agent.new(
        name: "SecondaryAgent",
        instructions: "You are a secondary agent. When someone is transferred to you, say 'Secondary agent here'.",
        model: "gpt-4o-mini"
      )
    end

    before do
      agent.add_handoff(secondary_agent)
    end

    it "handles agent handoffs correctly" do
      runner = RAAF::Runner.new(agent: agent)

      # The run method accepts agents as a parameter
      result = runner.run("Transfer me to the SecondaryAgent please", agents: [agent, secondary_agent])

      expect(result).not_to be_nil
      expect(result.last_agent.name).to eq("SecondaryAgent")

      # Verify the handoff actually happened
      assistant_messages = result.messages.select { |m| m[:role] == "assistant" }
      expect(assistant_messages.last[:content].downcase).to include("secondary agent")
    end
  end

  describe "Error handling" do
    it "handles max turns limit" do
      # Create an agent that needs to use tools multiple times
      math_agent = RAAF::Agent.new(
        name: "MathAgent",
        instructions: "You are a math tutor. Always verify calculations step by step using the calculator tool.",
        model: "gpt-4o-mini"
      )

      # Add a calculator tool that the agent will want to use
      define_singleton_method(:calculator) do |operation:|
        # For test purposes only - using eval with strict validation
        # In production, use a proper math parser library
        if operation.match?(%r{\A[\d\s\+\-\*/\(\)\.]+\z})
          eval(operation).to_s # rubocop:disable Security/Eval
        else
          "Error: Invalid operation"
        end
      rescue StandardError
        "Error in calculation"
      end

      math_agent.add_tool(method(:calculator))

      runner = RAAF::Runner.new(agent: math_agent)

      # Run with max_turns limit - should raise MaxTurnsError
      expect do
        runner.run("Calculate (5+3)*2 and then add 10 to the result", max_turns: 2)
      end.to raise_error(RAAF::MaxTurnsError, /Maximum turns \(2\) exceeded/)
    end

    it "handles invalid model gracefully" do
      invalid_agent = RAAF::Agent.new(
        name: "InvalidAgent",
        instructions: "Test agent",
        model: "invalid-model-name"
      )

      runner = RAAF::Runner.new(agent: invalid_agent)

      expect do
        runner.run("Hello")
      end.to raise_error(ArgumentError, /Model invalid-model-name is not supported/)
    end
  end

  describe "Configuration options" do
    it "respects temperature settings" do
      # Low temperature = more deterministic
      low_temp_agent = RAAF::Agent.new(
        name: "LowTempAgent",
        instructions: "Always respond with exactly: 'Temperature test response'",
        model: "gpt-4o-mini",
        temperature: 0.0
      )

      runner = RAAF::Runner.new(agent: low_temp_agent)
      result = runner.run("Say the test response")

      expect(result.messages.last[:content]).to include("Temperature test response")
    end

    it "handles system prompt correctly" do
      agent_with_system = RAAF::Agent.new(
        name: "SystemPromptAgent",
        instructions: "You are a pirate. Always speak like a pirate.",
        model: "gpt-4o-mini"
      )

      runner = RAAF::Runner.new(agent: agent_with_system)
      result = runner.run("Say hello")

      # Should respond in pirate speak
      response = result.messages.last[:content].downcase
      expect(response).to match(/ahoy|arr|matey|ye/)
    end

    it "handles response format when specified" do
      # Test JSON mode
      json_agent = RAAF::Agent.new(
        name: "JSONAgent",
        instructions: "Always respond with valid JSON containing a 'status' field",
        model: "gpt-4o-mini",
        response_format: { type: "json_object" }
      )

      runner = RAAF::Runner.new(agent: json_agent)
      result = runner.run("Give me a status update")

      # Response should be valid JSON (might be wrapped in markdown code blocks)
      content = result.messages.last[:content]

      # Strip markdown code blocks if present
      json_content = content.gsub(/```json\s*/, "").gsub(/```\s*$/, "").strip

      expect { JSON.parse(json_content) }.not_to raise_error
      parsed = JSON.parse(json_content)
      expect(parsed).to have_key("status")
    end
  end
end
