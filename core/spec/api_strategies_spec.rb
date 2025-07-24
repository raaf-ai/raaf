# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF API Strategies" do
  describe RAAF::Execution::BaseApiStrategy do
    let(:provider) { double("Provider") }
    let(:config) { RAAF::RunConfig.new(temperature: 0.7, max_tokens: 1000) }
    let(:strategy) { described_class.new(provider, config) }

    describe "#initialize" do
      it "stores provider and config" do
        expect(strategy.provider).to eq(provider)
        expect(strategy.config).to eq(config)
      end
    end

    describe "#execute" do
      it "raises NotImplementedError" do
        expect do
          strategy.execute([], double("Agent"), double("Runner"))
        end.to raise_error(NotImplementedError, "Subclasses must implement #execute")
      end
    end

    describe "#build_base_model_params" do
      let(:agent) { create_test_agent(name: "TestAgent") }
      let(:model_settings) { double("ModelSettings", to_h: { temperature: 0.5 }) }

      before do
        allow(config).to receive(:to_model_params).and_return({ max_tokens: 1000, temperature: 0.7 })
      end

      it "starts with config model parameters" do
        params = strategy.send(:build_base_model_params, agent)
        expect(params).to include(max_tokens: 1000, temperature: 0.7)
      end

      it "merges agent model settings when available" do
        allow(agent).to receive(:model_settings).and_return(model_settings)

        params = strategy.send(:build_base_model_params, agent)
        expect(params[:temperature]).to eq(0.5) # Agent setting overrides config
        expect(params[:max_tokens]).to eq(1000) # Config setting preserved
      end

      it "adds response format when agent has one" do
        response_format = { type: "json_object" }
        allow(agent).to receive(:response_format).and_return(response_format)

        params = strategy.send(:build_base_model_params, agent)
        expect(params[:response_format]).to eq(response_format)
      end

      it "adds tool choice when agent has one" do
        tool_choice = "auto"
        allow(agent).to receive(:respond_to?).with(:tool_choice).and_return(true)
        allow(agent).to receive(:tool_choice).and_return(tool_choice)

        params = strategy.send(:build_base_model_params, agent)
        expect(params[:tool_choice]).to eq(tool_choice)
      end

      it "handles agents without tool_choice method" do
        allow(agent).to receive(:respond_to?).with(:tool_choice).and_return(false)

        expect do
          strategy.send(:build_base_model_params, agent)
        end.not_to raise_error
      end

      it "ignores nil tool choice" do
        allow(agent).to receive(:respond_to?).with(:tool_choice).and_return(true)
        allow(agent).to receive(:tool_choice).and_return(nil)

        params = strategy.send(:build_base_model_params, agent)
        expect(params).not_to have_key(:tool_choice)
      end
    end

    describe "#extract_message_from_response" do
      it "extracts message from hash response with choices" do
        response = {
          choices: [
            {
              message: {
                role: "assistant",
                content: "Hello, world!"
              }
            }
          ]
        }

        message = strategy.send(:extract_message_from_response, response)
        expect(message).to eq({
                                role: "assistant",
                                content: "Hello, world!"
                              })
      end

      it "extracts message from hash response with first choice" do
        response = {
          choices: [
            {
              message: { role: "assistant", content: "First" }
            },
            {
              message: { role: "assistant", content: "Second" }
            }
          ]
        }

        message = strategy.send(:extract_message_from_response, response)
        expect(message[:content]).to eq("First")
      end

      it "handles response object with message method" do
        response = double("Response")
        allow(response).to receive(:is_a?).with(Hash).and_return(false)
        allow(response).to receive(:to_s).and_return("Response message")

        message = strategy.send(:extract_message_from_response, response)
        expect(message).to eq({ role: "assistant", content: "Response message" })
      end

      it "handles response object without message method" do
        response = double("Response")
        allow(response).to receive(:is_a?).with(Hash).and_return(false)
        allow(response).to receive(:to_s).and_return("Direct content")

        message = strategy.send(:extract_message_from_response, response)
        expect(message).to eq({
                                role: "assistant",
                                content: "Direct content"
                              })
      end

      it "handles empty or invalid responses" do
        expect(strategy.send(:extract_message_from_response, nil)).to eq({
                                                                           role: "assistant",
                                                                           content: ""
                                                                         })

        expect(strategy.send(:extract_message_from_response, {})).to eq({})
      end
    end

    describe "#extract_usage_from_response" do
      it "extracts usage from hash response" do
        response = { usage: { total_tokens: 100, prompt_tokens: 60, completion_tokens: 40 } }
        usage = strategy.send(:extract_usage_from_response, response)
        expect(usage).to eq({ total_tokens: 100, prompt_tokens: 60, completion_tokens: 40 })
      end

      it "extracts usage from response object" do
        usage_data = { total_tokens: 150 }
        response = { usage: usage_data }

        usage = strategy.send(:extract_usage_from_response, response)
        expect(usage).to eq(usage_data)
      end

      it "returns nil when no usage available" do
        expect(strategy.send(:extract_usage_from_response, nil)).to be_nil
        expect(strategy.send(:extract_usage_from_response, {})).to be_nil

        response = { other_key: "value" }
        expect(strategy.send(:extract_usage_from_response, response)).to be_nil
      end
    end
  end

  describe RAAF::Execution::ResponsesApiStrategy do
    let(:provider) { RAAF::Models::ResponsesProvider.new }
    let(:config) { RAAF::RunConfig.new(temperature: 0.8) }
    let(:strategy) { described_class.new(provider, config) }
    let(:agent) { create_test_agent(name: "ResponsesAgent") }
    let(:runner) { double("Runner") }
    let(:messages) { [{ role: "user", content: "Hello" }] }

    describe "#execute" do
      let(:mock_result) do
        double("RunResult",
               messages: messages + [{ role: "assistant", content: "Hi there!" }],
               usage: { total_tokens: 25 },
               last_agent: agent,
               turns: 1,
               tool_results: [])
      end

      before do
        allow(runner).to receive(:send).with(:execute_responses_api_core, messages, config, with_tracing: false)
                                       .and_return(mock_result)
      end

      it "delegates to runner's execute_responses_api_core method" do
        expect(runner).to receive(:send)
          .with(:execute_responses_api_core, messages, config, with_tracing: false)
          .and_return(mock_result)

        strategy.execute(messages, agent, runner)
      end

      it "returns properly formatted result" do
        result = strategy.execute(messages, agent, runner)

        expect(result).to eq({
                               conversation: messages + [{ role: "assistant", content: "Hi there!" }],
                               usage: { total_tokens: 25 },
                               final_result: true,
                               last_agent: agent,
                               turns: 1,
                               tool_results: []
                             })
      end

      it "logs debug information" do
        allow(strategy).to receive(:log_debug_api)

        strategy.execute(messages, agent, runner)

        expect(strategy).to have_received(:log_debug_api)
          .with("Using Responses API", provider: "RAAF::Models::ResponsesProvider")
      end

      it "handles runner errors gracefully" do
        allow(runner).to receive(:send).and_raise(StandardError, "API Error")

        expect do
          strategy.execute(messages, agent, runner)
        end.to raise_error(StandardError, "API Error")
      end
    end

    describe "#convert_response_to_messages" do
      context "with message output" do
        it "converts simple text output to messages" do
          response = {
            output: [
              {
                type: "message",
                role: "assistant",
                content: "Hello there!"
              }
            ]
          }

          messages = strategy.send(:convert_response_to_messages, response)

          expect(messages).to eq([{
                                   role: "assistant",
                                   content: "Hello there!"
                                 }])
        end

        it "converts array content format to messages" do
          response = {
            output: [
              {
                type: "message",
                role: "assistant",
                content: [
                  { type: "text", text: "Hello " },
                  { type: "text", text: "world!" }
                ]
              }
            ]
          }

          messages = strategy.send(:convert_response_to_messages, response)

          expect(messages.first[:content]).to eq("Hello world!")
        end

        it "handles output_text type" do
          response = {
            output: [
              { type: "output_text", content: "Text output" }
            ]
          }

          messages = strategy.send(:convert_response_to_messages, response)
          expect(messages.first[:content]).to eq("Text output")
        end
      end

      context "with function call output" do
        it "converts function calls to tool_calls format" do
          response = {
            output: [
              {
                type: "function_call",
                name: "get_weather",
                arguments: '{"location": "NYC"}',
                call_id: "call_123"
              }
            ]
          }

          messages = strategy.send(:convert_response_to_messages, response)

          expect(messages).to eq([{
                                   role: "assistant",
                                   content: "",
                                   tool_calls: [{
                                     "id" => "call_123",
                                     "function" => {
                                       "name" => "get_weather",
                                       "arguments" => '{"location": "NYC"}'
                                     }
                                   }]
                                 }])
        end

        it "handles multiple function calls" do
          response = {
            output: [
              {
                type: "function_call",
                name: "tool1",
                arguments: "{}",
                call_id: "call_1"
              },
              {
                type: "function_call",
                name: "tool2",
                arguments: "{}",
                call_id: "call_2"
              }
            ]
          }

          messages = strategy.send(:convert_response_to_messages, response)

          expect(messages.first[:tool_calls]).to have(2).items
          expect(messages.first[:tool_calls].map { |tc| tc["id"] }).to eq(%w[call_1 call_2])
        end

        it "combines text and function calls in one message" do
          response = {
            output: [
              { type: "message", content: "I'll help you with that." },
              {
                type: "function_call",
                name: "helper_tool",
                arguments: "{}",
                call_id: "call_help"
              }
            ]
          }

          messages = strategy.send(:convert_response_to_messages, response)

          expect(messages).to have(1).item
          expect(messages.first[:content]).to eq("I'll help you with that.")
          expect(messages.first[:tool_calls]).to have(1).item
        end
      end

      context "with edge cases" do
        it "handles empty output" do
          response = { output: [] }
          messages = strategy.send(:convert_response_to_messages, response)
          expect(messages).to eq([])
        end

        it "handles missing output" do
          response = {}
          messages = strategy.send(:convert_response_to_messages, response)
          expect(messages).to eq([])
        end

        it "handles nil response" do
          messages = strategy.send(:convert_response_to_messages, nil)
          expect(messages).to eq([])
        end

        it "handles unknown output types gracefully" do
          response = {
            output: [
              { type: "unknown_type", data: "some data" },
              { type: "message", content: "Known type" }
            ]
          }

          messages = strategy.send(:convert_response_to_messages, response)
          expect(messages.first[:content]).to eq("Known type")
        end

        it "works with string keys" do
          response = {
            "output" => [
              {
                "type" => "message",
                "content" => "String keys work too"
              }
            ]
          }

          messages = strategy.send(:convert_response_to_messages, response)
          expect(messages.first[:content]).to eq("String keys work too")
        end
      end
    end
  end

  describe RAAF::Execution::StandardApiStrategy do
    let(:provider) { double("Provider") }
    let(:config) { RAAF::RunConfig.new(stream: false) }
    let(:strategy) { described_class.new(provider, config) }
    let(:agent) { create_test_agent(name: "StandardAgent", model: "gpt-4") }
    let(:runner) { double("Runner") }
    let(:messages) { [{ role: "user", content: "Hello" }] }

    describe "#execute" do
      let(:api_response) do
        {
          choices: [
            {
              message: {
                role: "assistant",
                content: "Hello! How can I help?"
              }
            }
          ],
          usage: { total_tokens: 20 }
        }
      end

      before do
        allow(runner).to receive(:build_messages).and_return(messages)
        allow(strategy).to receive_messages(build_model_params: { temperature: 0.7 }, make_api_call: api_response)
      end

      it "builds model parameters from agent and config" do
        expect(strategy).to receive(:build_model_params).with(agent, runner).and_return({})
        strategy.execute(messages, agent, runner)
      end

      it "makes API call with correct parameters" do
        model_params = { temperature: 0.7, max_tokens: 1000 }
        allow(strategy).to receive(:build_model_params).and_return(model_params)

        expect(strategy).to receive(:make_api_call)
          .with(messages, "gpt-4", model_params)
          .and_return(api_response)

        strategy.execute(messages, agent, runner)
      end

      it "returns properly formatted result" do
        result = strategy.execute(messages, agent, runner)

        expect(result).to include(
          message: { role: "assistant", content: "Hello! How can I help?" },
          usage: { total_tokens: 20 },
          response: api_response
        )
      end

      it "handles API errors" do
        allow(strategy).to receive(:make_api_call).and_raise(StandardError, "API Error")

        expect do
          strategy.execute(messages, agent, runner)
        end.to raise_error(StandardError, "API Error")
      end
    end

    describe "#build_model_params" do
      let(:base_params) { { temperature: 0.7, max_tokens: 1000 } }

      before do
        allow(strategy).to receive(:build_base_model_params).and_return(base_params.dup)
      end

      it "starts with base model parameters" do
        expect(strategy).to receive(:build_base_model_params).with(agent)
        strategy.send(:build_model_params, agent, runner)
      end

      it "returns base model parameters when no prompt" do
        allow(agent).to receive(:prompt).and_return(nil)

        params = strategy.send(:build_model_params, agent, runner)
        expect(params).to eq(base_params)
      end

      it "adds prompt support when available" do
        prompt = { role: "system", content: "You are helpful" }
        allow(agent).to receive(:prompt).and_return(prompt)
        allow(provider).to receive(:respond_to?).with(:supports_prompts?).and_return(true)
        allow(provider).to receive(:supports_prompts?).and_return(true)

        # Mock PromptUtil
        stub_const("RAAF::Execution::PromptUtil", double)
        allow(RAAF::Execution::PromptUtil).to receive(:to_model_input)
          .with(prompt, nil, agent)
          .and_return("System prompt")

        params = strategy.send(:build_model_params, agent, runner)
        expect(params[:prompt]).to eq("System prompt")
      end

      it "skips prompt when provider doesn't support it" do
        allow(agent).to receive(:prompt).and_return({ content: "prompt" })
        allow(provider).to receive(:respond_to?).with(:supports_prompts?).and_return(false)

        params = strategy.send(:build_model_params, agent, runner)
        expect(params).not_to have_key(:prompt)
      end

      it "skips prompt when PromptUtil returns nil" do
        prompt = { role: "system", content: "You are helpful" }
        allow(agent).to receive(:prompt).and_return(prompt)
        allow(provider).to receive(:respond_to?).with(:supports_prompts?).and_return(true)
        allow(provider).to receive(:supports_prompts?).and_return(true)

        # Mock PromptUtil
        stub_const("RAAF::Execution::PromptUtil", double)
        allow(RAAF::Execution::PromptUtil).to receive(:to_model_input)
          .with(prompt, nil, agent)
          .and_return(nil)

        params = strategy.send(:build_model_params, agent, runner)
        expect(params).not_to have_key(:prompt)
      end
    end

    describe "#make_api_call" do
      let(:api_messages) { [{ role: "user", content: "Test" }] }
      let(:model) { "gpt-4" }
      let(:model_params) { { temperature: 0.5 } }

      context "with streaming enabled" do
        let(:config) { RAAF::RunConfig.new(stream: true) }

        it "calls stream_completion" do
          expect(provider).to receive(:stream_completion)
            .with(messages: api_messages, model: model, **model_params)

          strategy.send(:make_api_call, api_messages, model, model_params)
        end
      end

      context "with streaming disabled" do
        let(:config) { RAAF::RunConfig.new(stream: false) }

        it "calls complete" do
          expect(provider).to receive(:complete)
            .with(messages: api_messages, model: model, **model_params)

          strategy.send(:make_api_call, api_messages, model, model_params)
        end
      end
    end
  end

  describe RAAF::Execution::ApiStrategyFactory do
    let(:config) { RAAF::RunConfig.new }

    describe ".create" do
      it "creates ResponsesApiStrategy for ResponsesProvider" do
        provider = RAAF::Models::ResponsesProvider.new
        strategy = described_class.create(provider, config)

        expect(strategy).to be_a(RAAF::Execution::ResponsesApiStrategy)
        expect(strategy.provider).to eq(provider)
        expect(strategy.config).to eq(config)
      end

      it "creates StandardApiStrategy for other providers" do
        provider = RAAF::Models::OpenAIProvider.new
        strategy = described_class.create(provider, config)

        expect(strategy).to be_a(RAAF::Execution::StandardApiStrategy)
        expect(strategy.provider).to eq(provider)
        expect(strategy.config).to eq(config)
      end

      it "creates StandardApiStrategy for custom providers" do
        provider = double("CustomProvider")
        strategy = described_class.create(provider, config)

        expect(strategy).to be_a(RAAF::Execution::StandardApiStrategy)
      end

      it "handles nil provider gracefully" do
        expect do
          described_class.create(nil, config)
        end.not_to raise_error

        strategy = described_class.create(nil, config)
        expect(strategy).to be_a(RAAF::Execution::StandardApiStrategy)
      end
    end
  end
end
