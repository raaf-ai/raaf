# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Provider Communication", :integration do
  let(:agent) { create_test_agent(name: "IntegrationTestAgent") }
  let(:runner) { RAAF::Runner.new(agent: agent, provider: create_mock_provider) }

  describe "OpenAI Responses API integration" do
    it "successfully communicates with provider" do
      mock_provider = create_mock_provider
      mock_provider.add_response("Hello! How can I help you today?")

      test_runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      result = test_runner.run("Say hello")

      expect(result).to be_a(RAAF::Result)
      expect(result.messages).not_to be_empty
      expect(result.usage[:total_tokens]).to be_positive
      expect(result.success?).to be true
    end

    it "handles provider errors gracefully" do
      mock_provider = create_mock_provider
      mock_provider.add_error(RAAF::Models::APIError.new("Model not supported"))

      test_runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      expect do
        test_runner.run("Test message")
      end.to raise_error(RAAF::Models::APIError, /Model not supported/)
    end

    it "respects rate limiting" do
      # This test would require actual API calls to test rate limiting
      # In practice, this should be tested with recorded responses
      skip "Rate limiting test requires real API calls or complex mocking"
    end
  end

  describe "Tool integration" do
    let(:weather_tool) do
      RAAF::FunctionTool.new(
        proc { |location| "Weather in #{location}: sunny, 72°F" },
        name: "get_weather",
        description: "Get weather for a location",
        parameters: {
          type: "object",
          properties: {
            location: { type: "string", description: "The location to get weather for" }
          },
          required: ["location"]
        }
      )
    end

    let(:agent_with_tools) do
      agent = create_test_agent(name: "WeatherAgent")
      agent.add_tool(weather_tool)
      agent
    end

    it "executes tools correctly" do
      mock_provider = create_mock_provider
      mock_provider.add_response(
        "I'll check the weather for you.",
        tool_calls: [{
          function: { name: "get_weather", arguments: '{"location": "New York"}' },
          id: "call_123"
        }]
      )
      mock_provider.add_response("The weather in New York is sunny and 72°F.")

      test_runner = RAAF::Runner.new(agent: agent_with_tools, provider: mock_provider)
      result = test_runner.run("What's the weather like in New York?")

      expect(result.success?).to be true
      expect(result.messages).not_to be_empty
      # Should contain responses mentioning the weather
      content = result.messages.map { |m| m[:content] }.compact.join(" ")
      expect(content).to match(/weather|sunny|temperature/i)
    end
  end

  describe "Context handling" do
    it "maintains conversation context" do
      # Use mock provider for this test since it requires context persistence
      mock_provider = create_mock_provider
      mock_provider.add_response("Nice to meet you, Alice!")
      mock_provider.add_response("Your name is Alice, as you mentioned earlier.")

      test_runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      # First message
      result1 = test_runner.run("My name is Alice")
      expect(result1.success?).to be true

      # Second message should remember the name - simulate context passing
      result2 = test_runner.run("What's my name?", previous_messages: result1.messages)
      expect(result2.success?).to be true

      # Debug: check the messages structure
      last_message = result2.messages.last
      content = last_message[:content] || last_message["content"] || ""
      expect(content.to_s).to match(/alice/i)
    end
  end
end
