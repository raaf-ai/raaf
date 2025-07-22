# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::ResponsesProvider do
  let(:api_key) { "sk-test-key" }
  let(:provider) { described_class.new(api_key: api_key) }

  describe "#initialize" do
    it "requires API key" do
      allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return(nil)

      expect do
        described_class.new
      end.to raise_error(RAAF::Models::AuthenticationError, /API key is required/)
    end

    it "accepts API key parameter" do
      provider = described_class.new(api_key: "sk-test")
      expect(provider.instance_variable_get(:@api_key)).to eq("sk-test")
    end

    it "reads API key from environment" do
      allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return("sk-env-key")
      allow(ENV).to receive(:[]).with("OPENAI_API_BASE").and_return(nil)

      provider = described_class.new
      expect(provider.instance_variable_get(:@api_key)).to eq("sk-env-key")
    end

    it "uses default API base" do
      provider = described_class.new(api_key: "sk-test")
      expect(provider.instance_variable_get(:@api_base)).to eq("https://api.openai.com/v1")
    end

    it "accepts custom API base" do
      provider = described_class.new(api_key: "sk-test", api_base: "https://custom.api.com")
      expect(provider.instance_variable_get(:@api_base)).to eq("https://custom.api.com")
    end

    it "reads API base from environment" do
      allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return("sk-test")
      allow(ENV).to receive(:[]).with("OPENAI_API_BASE").and_return("https://env.api.com")

      provider = described_class.new
      expect(provider.instance_variable_get(:@api_base)).to eq("https://env.api.com")
    end
  end

  describe "#supported_models" do
    it "returns array of supported models" do
      models = provider.supported_models

      expect(models).to include("gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4")
      expect(models).to include("o1-preview", "o1-mini")
      expect(models).to be_frozen
    end
  end

  describe "#provider_name" do
    it "returns OpenAI" do
      expect(provider.provider_name).to eq("OpenAI")
    end
  end

  describe "#supports_prompts?" do
    it "returns true" do
      expect(provider.supports_prompts?).to be true
    end
  end

  describe "#supports_function_calling?" do
    it "returns true" do
      expect(provider.supports_function_calling?).to be true
    end
  end

  describe "#validate_model" do
    it "accepts supported models" do
      expect { provider.send(:validate_model, "gpt-4o") }.not_to raise_error
      expect { provider.send(:validate_model, "gpt-4") }.not_to raise_error
    end

    it "rejects unsupported models" do
      expect do
        provider.send(:validate_model, "unsupported-model")
      end.to raise_error(ArgumentError, /not supported/)
    end
  end

  describe "#responses_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "gpt-4o" }

    it "validates model before making request" do
      expect do
        provider.responses_completion(messages: messages, model: "invalid-model")
      end.to raise_error(ArgumentError, /not supported/)
    end

    it "accepts valid parameters" do
      # Mock the API call to avoid actual HTTP requests
      allow(provider).to receive(:call_responses_api).and_return({
                                                                   id: "resp_123",
                                                                   output: [{ type: "message", role: "assistant", content: "Hello!" }],
                                                                   usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 }
                                                                 })

      result = provider.responses_completion(messages: messages, model: model)

      expect(result).to include(:id, :output, :usage)
      expect(result[:id]).to eq("resp_123")
      expect(result[:output]).to be_an(Array)
      expect(result[:usage]).to be_a(Hash)
    end
  end

  describe "#stream_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "gpt-4o" }

    it "validates model before streaming" do
      expect do
        provider.stream_completion(messages: messages, model: "invalid-model") {}
      end.to raise_error(ArgumentError, /not supported/)
    end

    it "delegates to responses_completion with stream enabled" do
      expect(provider).to receive(:responses_completion).with(
        messages: messages,
        model: model,
        tools: nil,
        stream: true
      )

      provider.stream_completion(messages: messages, model: model) {}
    end
  end

  describe "message conversion" do
    describe "#convert_messages_to_input" do
      it "converts user messages to input items" do
        messages = [{ role: "user", content: "Hello" }]

        input = provider.send(:convert_messages_to_input, messages)

        expect(input).to be_an(Array)
        expect(input.first[:type]).to eq("user_text")
        expect(input.first[:text]).to eq("Hello")
      end

      it "converts assistant messages with tool calls" do
        messages = [
          {
            role: "assistant",
            content: "I'll help you with that",
            tool_calls: [
              {
                id: "call_123",
                type: "function",
                function: { name: "get_weather", arguments: '{"location": "NYC"}' }
              }
            ]
          }
        ]

        input = provider.send(:convert_messages_to_input, messages)

        expect(input).to be_an(Array)
        
        # When assistant message has both content and tool_calls,
        # content is added first as a message, then the function_call
        expect(input.length).to eq(2)
        expect(input[0][:type]).to eq("message")
        expect(input[0][:text]).to eq("I'll help you with that")
        
        expect(input[1][:type]).to eq("function_call")
        expect(input[1][:name]).to eq("get_weather")
        expect(input[1][:call_id]).to eq("call_123")
      end

      it "converts tool result messages" do
        messages = [
          {
            role: "tool",
            content: "The weather is sunny",
            tool_call_id: "call_123"
          }
        ]

        input = provider.send(:convert_messages_to_input, messages)

        expect(input.first[:type]).to eq("function_call_output")
        expect(input.first[:call_id]).to eq("call_123")
        expect(input.first[:output]).to eq("The weather is sunny")
      end
    end

    describe "#extract_system_instructions" do
      it "extracts system message content" do
        messages = [
          { role: "system", content: "You are a helpful assistant" },
          { role: "user", content: "Hello" }
        ]

        instructions = provider.send(:extract_system_instructions, messages)

        expect(instructions).to eq("You are a helpful assistant")
      end

      it "returns nil when no system message" do
        messages = [{ role: "user", content: "Hello" }]

        instructions = provider.send(:extract_system_instructions, messages)

        expect(instructions).to be_nil
      end
    end
  end

  describe "tool conversion" do
    describe "#convert_tools" do
      it "returns empty hash for nil tools" do
        result = provider.send(:convert_tools, nil)
        expect(result).to eq({ tools: [], includes: [] })
      end

      it "returns empty hash for empty tools" do
        result = provider.send(:convert_tools, [])
        expect(result).to eq({ tools: [], includes: [] })
      end

      it "converts FunctionTool objects" do
        tool = RAAF::FunctionTool.new(proc { |x| x }, name: "test_tool")

        result = provider.send(:convert_tools, [tool])

        expect(result).to be_a(Hash)
        expect(result).to have_key(:tools)
        expect(result).to have_key(:includes)
        expect(result[:tools].first[:type]).to eq("function")
        expect(result[:tools].first[:name]).to eq("test_tool")
      end

      it "passes through hash tools" do
        tool_hash = { type: "function", function: { name: "test", parameters: {} } }

        result = provider.send(:convert_tools, [tool_hash])

        expect(result).to be_a(Hash)
        expect(result).to have_key(:tools)
        expect(result).to have_key(:includes)
        expect(result[:tools]).to include(tool_hash)
      end
    end

    describe "#convert_tool_choice" do
      it "returns auto for nil tool_choice" do
        result = provider.send(:convert_tool_choice, nil)
        expect(result).to eq("auto")
      end

      it "converts string tool_choice to object format" do
        result = provider.send(:convert_tool_choice, "get_weather")

        expect(result).to be_a(Hash)
        expect(result[:type]).to eq("function")
        expect(result[:name]).to eq("get_weather")
      end

      it "passes through hash tool_choice" do
        tool_choice = { type: "function", function: { name: "test" } }

        result = provider.send(:convert_tool_choice, tool_choice)

        expect(result).to eq(tool_choice)
      end
    end
  end

  describe "response format conversion" do
    describe "#convert_response_format" do
      it "returns nil for nil response_format" do
        result = provider.send(:convert_response_format, nil)
        expect(result).to be_nil
      end

      it "converts response_format to format structure" do
        response_format = {
          type: "json_schema",
          json_schema: {
            name: "TestSchema",
            schema: { type: "object" },
            strict: true
          }
        }

        result = provider.send(:convert_response_format, response_format)

        expect(result).to be_a(Hash)
        expect(result).to have_key(:format)
        expect(result[:format]).to have_key(:type)
        expect(result[:format][:type]).to eq("json_schema")
      end
    end
  end

  describe "parameter preparation" do
    describe "#prepare_function_parameters" do
      it "ensures additionalProperties is false for strict mode" do
        parameters = { type: "object", properties: { name: { type: "string" } } }

        result = provider.send(:prepare_function_parameters, parameters)

        expect(result[:additionalProperties]).to be false
      end

      it "preserves existing additionalProperties setting" do
        parameters = {
          type: "object",
          properties: { name: { type: "string" } },
          additionalProperties: true
        }

        result = provider.send(:prepare_function_parameters, parameters)

        expect(result[:additionalProperties]).to be true
      end
    end

    describe "#determine_strict_mode" do
      it "returns true when additionalProperties is false and has properties and required" do
        parameters = {
          type: "object",
          properties: { name: { type: "string" } },
          additionalProperties: false,
          required: ["name"]
        }

        result = provider.send(:determine_strict_mode, parameters)

        expect(result).to be true
      end

      it "returns false when additionalProperties is true" do
        parameters = { type: "object", additionalProperties: true }

        result = provider.send(:determine_strict_mode, parameters)

        expect(result).to be false
      end
    end
  end
end
