# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe RAAF::Models::ResponsesProvider, "Enhanced Coverage Tests" do
  let(:api_key) { "sk-test-key" }
  let(:provider) { described_class.new(api_key: api_key) }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.reset!
  end

  describe "#responses_completion - comprehensive parameter testing" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "gpt-4o" }

    let(:mock_response) do
      {
        id: "resp_test_123",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "Hello! How can I help you?" }]
          }
        ],
        usage: { input_tokens: 15, output_tokens: 25, total_tokens: 40 }
      }
    end

    context "with tools parameter" do
      let(:tools) do
        [
          {
            type: "function",
            function: {
              name: "get_weather",
              description: "Get current weather",
              parameters: {
                type: "object",
                properties: { location: { type: "string" } },
                required: ["location"]
              }
            }
          }
        ]
      end

      it "processes tools parameter correctly" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: mock_response.to_json)

        result = provider.responses_completion(
          messages: messages,
          model: model,
          tools: tools
        )

        expect(result).to include(:id, :output, :usage)
        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
          .with(body: hash_including("tools"))
      end
    end

    context "with previous_response_id" do
      it "includes previous response ID in request" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: mock_response.to_json)

        provider.responses_completion(
          messages: messages,
          model: model,
          previous_response_id: "resp_previous_123"
        )

        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
          .with(body: hash_including("previous_response_id"))
      end
    end

    context "with direct input parameter" do
      let(:input_items) do
        [
          { type: "user_text", text: "Direct input message" },
          { type: "function_call_output", output: "Function result" }
        ]
      end

      it "uses direct input instead of converting messages" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: mock_response.to_json)

        result = provider.responses_completion(
          messages: [],  # Empty since using direct input
          model: model,
          input: input_items
        )

        expect(result).to include(:id, :output)
        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
          .with(body: hash_including("input"))
      end
    end

    context "with additional parameters" do
      it "handles temperature, max_tokens, and other options" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: mock_response.to_json)

        provider.responses_completion(
          messages: messages,
          model: model,
          temperature: 0.7,
          max_tokens: 150,
          top_p: 0.9,
          frequency_penalty: 0.1,
          presence_penalty: 0.1
        )

        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
          .with(body: hash_including("temperature", "max_tokens", "top_p"))
      end
    end
  end

  describe "API communication - HTTP request/response handling" do
    let(:messages) { [{ role: "user", content: "Test message" }] }
    let(:model) { "gpt-4o" }

    context "successful API responses" do
      it "handles 200 OK responses correctly" do
        response_body = {
          id: "resp_success_123",
          output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Success!" }] }],
          usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 }
        }

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })

        result = provider.responses_completion(messages: messages, model: model)

        expect(result[:id]).to eq("resp_success_123")
        expect(result[:output]).to be_an(Array)
        expect(result[:usage][:total_tokens]).to eq(15)
      end

      it "handles 201 Created responses" do
        response_body = { id: "resp_created", output: [], usage: {} }

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 201, body: response_body.to_json)

        result = provider.responses_completion(messages: messages, model: model)
        expect(result[:id]).to eq("resp_created")
      end
    end

    context "API error responses" do
      it "handles 400 Bad Request errors" do
        error_body = {
          error: {
            message: "Invalid request format",
            type: "invalid_request_error",
            code: "bad_request"
          }
        }

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 400, body: error_body.to_json)

        expect {
          provider.responses_completion(messages: messages, model: model)
        }.to raise_error(RAAF::Models::APIError, /Invalid request format/)
      end

      it "handles 401 Unauthorized errors" do
        error_body = {
          error: {
            message: "Invalid API key",
            type: "authentication_error"
          }
        }

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 401, body: error_body.to_json)

        expect {
          provider.responses_completion(messages: messages, model: model)
        }.to raise_error(RAAF::Models::APIError, /Invalid API key/)
      end

      it "handles 429 Rate Limit errors" do
        error_body = {
          error: {
            message: "Rate limit exceeded",
            type: "rate_limit_error"
          }
        }

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 429, body: error_body.to_json)

        expect {
          provider.responses_completion(messages: messages, model: model)
        }.to raise_error(RAAF::Models::RetryableProvider::RetryableError)
      end

      it "handles 500 Internal Server errors" do
        error_body = {
          error: {
            message: "Internal server error",
            type: "server_error"
          }
        }

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 500, body: error_body.to_json)

        expect {
          provider.responses_completion(messages: messages, model: model)
        }.to raise_error(RAAF::Models::RetryableProvider::RetryableError)
      end

      it "handles non-JSON error responses" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 503, body: "Service Temporarily Unavailable")

        expect {
          provider.responses_completion(messages: messages, model: model)
        }.to raise_error(RAAF::Models::RetryableProvider::RetryableError)
      end
    end

    context "network and timeout errors" do
      it "handles connection timeouts" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_timeout

        expect {
          provider.responses_completion(messages: messages, model: model)
        }.to raise_error(Timeout::Error)
      end

      it "handles connection refused errors" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_raise(Errno::ECONNREFUSED)

        expect {
          provider.responses_completion(messages: messages, model: model)
        }.to raise_error(Errno::ECONNREFUSED)
      end

      it "handles DNS resolution errors" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_raise(SocketError.new("Failed to open TCP connection"))

        expect {
          provider.responses_completion(messages: messages, model: model)
        }.to raise_error(SocketError)
      end
    end
  end

  describe "tool conversion system - comprehensive coverage" do
    let(:messages) { [{ role: "user", content: "Test" }] }
    let(:model) { "gpt-4o" }

    context "with various tool formats" do
      it "converts hash-based tools" do
        tools = [
          {
            type: "function",
            function: {
              name: "calculator",
              description: "Performs calculations",
              parameters: {
                type: "object",
                properties: { expression: { type: "string" } },
                required: ["expression"]
              }
            }
          }
        ]

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

        provider.responses_completion(messages: messages, model: model, tools: tools)

        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
          .with(body: hash_including("tools"))
      end

      it "converts FunctionTool objects" do
        function_tool = RAAF::FunctionTool.new(
          proc { |text:| text.upcase },
          name: "upcase",
          description: "Convert text to uppercase"
        )

        tools = [function_tool]

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

        provider.responses_completion(messages: messages, model: model, tools: tools)

        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
          .with(body: hash_including("tools"))
      end

      it "handles web search tools specially" do
        # Mock a web search tool
        web_search_tool = double("WebSearchTool")
        allow(web_search_tool).to receive(:class).and_return(Object) # Simulate class check
        allow(web_search_tool).to receive(:to_s).and_return("WebSearchTool")
        allow(web_search_tool).to receive(:respond_to?).with(:tool_definition).and_return(false)
        allow(web_search_tool).to receive(:respond_to?).with(:to_tool_definition).and_return(true)
        allow(web_search_tool).to receive(:to_tool_definition).and_return({
          type: "web_search"
        })

        # Simulate web search tool detection
        tools = [web_search_tool]

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

        # This might trigger special web search handling
        provider.responses_completion(messages: messages, model: model, tools: tools)

        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
      end

      it "handles tools with tool_definition method" do
        dsl_tool = double("DSLTool")
        allow(dsl_tool).to receive(:respond_to?).with(:tool_definition).and_return(true)
        allow(dsl_tool).to receive(:tool_definition).and_return({
          type: "function",
          function: { name: "dsl_tool", description: "DSL tool", parameters: {} }
        })

        tools = [dsl_tool]

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

        provider.responses_completion(messages: messages, model: model, tools: tools)

        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
          .with(body: hash_including("tools"))
      end

      it "handles tools with to_tool_definition method" do
        custom_tool = double("CustomTool")
        allow(custom_tool).to receive(:respond_to?).with(:tool_definition).and_return(false)
        allow(custom_tool).to receive(:respond_to?).with(:to_tool_definition).and_return(true)
        allow(custom_tool).to receive(:to_tool_definition).and_return({
          type: "function",
          function: { name: "custom_tool", description: "Custom tool", parameters: {} }
        })

        tools = [custom_tool]

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

        provider.responses_completion(messages: messages, model: model, tools: tools)

        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
          .with(body: hash_including("tools"))
      end

      it "raises error for unknown tool types" do
        unknown_tool = "not_a_tool"
        tools = [unknown_tool]

        expect {
          provider.responses_completion(messages: messages, model: model, tools: tools)
        }.to raise_error(ArgumentError, /Unknown tool type/)
      end
    end
  end

  describe "message format conversion - comprehensive scenarios" do
    context "convert_messages_to_input with various message types" do
      it "converts user messages correctly" do
        messages = [
          { role: "user", content: "Hello" },
          { role: "user", content: "How are you?" }
        ]

        input = provider.send(:convert_messages_to_input, messages)

        expect(input).to be_an(Array)
        expect(input.length).to eq(2)
        expect(input[0][:type]).to eq("user_text")
        expect(input[0][:text]).to eq("Hello")
        expect(input[1][:text]).to eq("How are you?")
      end

      it "converts assistant messages correctly" do
        messages = [
          { role: "assistant", content: "Hi there!" },
          { role: "assistant", content: "I'm doing well." }
        ]

        input = provider.send(:convert_messages_to_input, messages)

        expect(input.length).to eq(2)
        expect(input[0][:type]).to eq("message")
        expect(input[0][:role]).to eq("assistant")
        expect(input[0][:content]).to eq([{ type: "text", text: "Hi there!" }])
      end

      it "converts tool messages correctly" do
        messages = [
          { role: "tool", content: "Tool result", tool_call_id: "call_123" }
        ]

        input = provider.send(:convert_messages_to_input, messages)

        expect(input.length).to eq(1)
        expect(input[0][:type]).to eq("function_call_output")
        expect(input[0][:output]).to eq("Tool result")
        expect(input[0][:call_id]).to eq("call_123")
      end

      it "handles messages with tool calls" do
        messages = [
          {
            role: "assistant",
            content: "I'll check the weather",
            tool_calls: [
              {
                id: "call_weather_123",
                type: "function",
                function: { name: "get_weather", arguments: '{"location": "NYC"}' }
              }
            ]
          }
        ]

        input = provider.send(:convert_messages_to_input, messages)

        expect(input.length).to eq(2) # Message + tool call
        expect(input[0][:type]).to eq("message")
        expect(input[1][:type]).to eq("function_call")
        expect(input[1][:name]).to eq("get_weather")
        expect(input[1][:arguments]).to eq(JSON.parse('{"location": "NYC"}'))
      end

      it "handles mixed message types in sequence" do
        messages = [
          { role: "user", content: "What's the weather?" },
          { role: "assistant", content: "I'll check", tool_calls: [
            { id: "call_1", type: "function", function: { name: "weather", arguments: "{}" }}
          ]},
          { role: "tool", content: "Sunny, 72F", tool_call_id: "call_1" },
          { role: "assistant", content: "It's sunny and 72F!" }
        ]

        input = provider.send(:convert_messages_to_input, messages)

        expect(input.length).to eq(5) # user + assistant content + tool_call + tool_result + final assistant
        expect(input[0][:type]).to eq("user_text")
        expect(input[1][:type]).to eq("message")
        expect(input[2][:type]).to eq("function_call")
        expect(input[3][:type]).to eq("function_call_output")
        expect(input[4][:type]).to eq("message")
      end
    end

    context "system instruction extraction" do
      it "extracts system instructions from messages" do
        messages = [
          { role: "system", content: "You are a helpful assistant." },
          { role: "user", content: "Hello" }
        ]

        instructions = provider.send(:extract_system_instructions, messages)
        expect(instructions).to eq("You are a helpful assistant.")
      end

      it "handles missing system messages" do
        messages = [{ role: "user", content: "Hello" }]

        instructions = provider.send(:extract_system_instructions, messages)
        expect(instructions).to be_nil
      end

      it "uses the first system message when multiple exist" do
        messages = [
          { role: "system", content: "First instruction" },
          { role: "system", content: "Second instruction" },
          { role: "user", content: "Hello" }
        ]

        instructions = provider.send(:extract_system_instructions, messages)
        expect(instructions).to eq("First instruction")
      end
    end
  end

  describe "parameter preparation and validation" do
    context "function parameter processing" do
      it "prepares function parameters correctly" do
        params = {
          type: "object",
          properties: {
            location: { type: "string", description: "City name" },
            unit: { type: "string", enum: ["celsius", "fahrenheit"] }
          },
          required: ["location"]
        }

        prepared = provider.send(:prepare_function_parameters, params)

        expect(prepared).to include(:type, :properties)
        expect(prepared[:additionalProperties]).to be false
      end

      it "handles parameters without required fields" do
        params = {
          type: "object",
          properties: {
            optional_param: { type: "string" }
          }
        }

        prepared = provider.send(:prepare_function_parameters, params)

        expect(prepared[:required]).to eq([])
      end

      it "determines strict mode correctly" do
        # Strict mode conditions
        strict_params = {
          type: "object",
          properties: { param: { type: "string" } },
          required: ["param"],
          additionalProperties: false
        }

        expect(provider.send(:determine_strict_mode, strict_params)).to be true

        # Non-strict mode
        non_strict_params = { type: "object", properties: {} }
        expect(provider.send(:determine_strict_mode, non_strict_params)).to be false
      end
    end

    context "format converters" do
      it "converts tool choice to proper format" do
        # Auto choice
        expect(provider.send(:convert_tool_choice, "auto")).to eq("auto")

        # Required choice
        expect(provider.send(:convert_tool_choice, "required")).to eq("required")

        # Function choice
        choice_hash = { type: "function", function: { name: "my_tool" } }
        result = provider.send(:convert_tool_choice, choice_hash)
        expect(result).to eq(choice_hash)
      end

      it "converts response format correctly" do
        json_schema = {
          type: "json_schema",
          json_schema: {
            name: "response_format",
            schema: { type: "object", properties: {} }
          }
        }

        result = provider.send(:convert_response_format, json_schema)
        expect(result).to eq(json_schema)
      end
    end
  end

  describe "streaming functionality" do
    let(:messages) { [{ role: "user", content: "Stream test" }] }
    let(:model) { "gpt-4o" }

    context "stream_completion method" do
      it "enables streaming in responses_completion" do
        expect(provider).to receive(:responses_completion).with(
          messages: messages,
          model: model,
          tools: nil,
          stream: true
        )

        provider.stream_completion(messages: messages, model: model) {}
      end

      it "passes tools parameter to streaming" do
        tools = [{ type: "function", function: { name: "test" } }]

        expect(provider).to receive(:responses_completion).with(
          messages: messages,
          model: model,
          tools: tools,
          stream: true
        )

        provider.stream_completion(messages: messages, model: model, tools: tools) {}
      end
    end

    # Note: Full streaming tests would require more complex SSE mocking
    # These tests focus on the streaming delegation and parameter handling
  end

  describe "edge cases and error handling" do
    let(:messages) { [{ role: "user", content: "Test" }] }
    let(:model) { "gpt-4o" }

    context "malformed responses" do
      it "handles non-JSON response bodies" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: "Not JSON")

        expect {
          provider.responses_completion(messages: messages, model: model)
        }.to raise_error(JSON::ParserError)
      end

      it "handles empty response bodies" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: "")

        expect {
          provider.responses_completion(messages: messages, model: model)
        }.to raise_error(JSON::ParserError)
      end
    end

    context "parameter edge cases" do
      it "handles empty messages array" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

        result = provider.responses_completion(messages: [], model: model)
        expect(result[:id]).to eq("test")
      end

      it "handles messages with missing content" do
        messages_with_missing_content = [
          { role: "user" }, # Missing content
          { role: "assistant", content: "Response" }
        ]

        expect {
          provider.send(:convert_messages_to_input, messages_with_missing_content)
        }.not_to raise_error
      end

      it "handles very large message content" do
        large_content = "x" * 10000
        large_messages = [{ role: "user", content: large_content }]

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

        expect {
          provider.responses_completion(messages: large_messages, model: model)
        }.not_to raise_error
      end

      it "handles Unicode and special characters" do
        unicode_messages = [{ role: "user", content: "Hello 🌍 こんにちは" }]

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

        expect {
          provider.responses_completion(messages: unicode_messages, model: model)
        }.not_to raise_error
      end
    end
  end

  describe "authentication and headers" do
    let(:messages) { [{ role: "user", content: "Test" }] }
    let(:model) { "gpt-4o" }

    it "includes correct authorization header" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      provider.responses_completion(messages: messages, model: model)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with(headers: { 'Authorization' => 'Bearer sk-test-key' })
    end

    it "includes correct content-type header" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      provider.responses_completion(messages: messages, model: model)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with(headers: { 'Content-Type' => 'application/json' })
    end

    it "includes user-agent header" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      provider.responses_completion(messages: messages, model: model)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with(headers: { 'User-Agent' => /Agents/ })
    end
  end

  describe "performance and optimization" do
    let(:messages) { [{ role: "user", content: "Performance test" }] }
    let(:model) { "gpt-4o" }

    it "completes requests within reasonable time" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      start_time = Time.now
      provider.responses_completion(messages: messages, model: model)
      duration = Time.now - start_time

      expect(duration).to be < 1.0 # Should complete within 1 second (mocked)
    end

    it "handles multiple simultaneous requests" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      threads = []
      results = []

      5.times do |i|
        threads << Thread.new do
          result = provider.responses_completion(
            messages: [{ role: "user", content: "Request #{i}" }],
            model: model
          )
          results << result
        end
      end

      threads.each(&:join)

      expect(results.length).to eq(5)
      results.each { |result| expect(result[:id]).to eq("test") }
    end
  end
end