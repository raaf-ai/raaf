# frozen_string_literal: true

require "spec_helper"
require "raaf/models/responses_provider"
require "webmock/rspec"

RSpec.describe RAAF::Models::ResponsesProvider, "#unsupported_parameters" do
  let(:api_key) { "test-api-key" }
  let(:provider) { described_class.new(api_key: api_key) }

  before do
    # Stub the OpenAI API endpoint
    stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return(
        status: 200,
        body: {
          id: "resp_test123",
          status: "completed",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "Hello!" }]
            }
          ],
          usage: { prompt_tokens: 10, output_tokens: 5, total_tokens: 15 }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "unsupported parameter warnings" do
    it "warns about frequency_penalty" do
      expect(provider).to receive(:log_warn).with(
        "⚠️ Parameter 'frequency_penalty' is not supported by OpenAI Responses API",
        hash_including(
          parameter: :frequency_penalty,
          value: 0.5,
          suggestion: "Remove this parameter or use Chat Completions API (OpenAIProvider) instead"
        )
      )

      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-4o",
        frequency_penalty: 0.5
      )
    end

    it "warns about presence_penalty" do
      expect(provider).to receive(:log_warn).with(
        "⚠️ Parameter 'presence_penalty' is not supported by OpenAI Responses API",
        hash_including(
          parameter: :presence_penalty,
          value: 0.3,
          suggestion: "Remove this parameter or use Chat Completions API (OpenAIProvider) instead"
        )
      )

      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-4o",
        presence_penalty: 0.3
      )
    end

    it "warns about best_of" do
      expect(provider).to receive(:log_warn).with(
        "⚠️ Parameter 'best_of' is not supported by OpenAI Responses API",
        hash_including(
          parameter: :best_of,
          value: 3,
          suggestion: "Remove this parameter or use Chat Completions API (OpenAIProvider) instead"
        )
      )

      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-4o",
        best_of: 3
      )
    end

    it "warns about logit_bias" do
      expect(provider).to receive(:log_warn).with(
        "⚠️ Parameter 'logit_bias' is not supported by OpenAI Responses API",
        hash_including(
          parameter: :logit_bias,
          value: { "50256" => -100 },
          suggestion: "Remove this parameter or use Chat Completions API (OpenAIProvider) instead"
        )
      )

      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-4o",
        logit_bias: { "50256" => -100 }
      )
    end

    it "warns about multiple unsupported parameters at once" do
      expect(provider).to receive(:log_warn).with(
        "⚠️ Parameter 'frequency_penalty' is not supported by OpenAI Responses API",
        hash_including(parameter: :frequency_penalty)
      )
      expect(provider).to receive(:log_warn).with(
        "⚠️ Parameter 'presence_penalty' is not supported by OpenAI Responses API",
        hash_including(parameter: :presence_penalty)
      )

      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-4o",
        frequency_penalty: 0.5,
        presence_penalty: 0.3
      )
    end

    it "does not warn when unsupported parameters are nil" do
      expect(provider).not_to receive(:log_warn)

      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-4o",
        frequency_penalty: nil,
        presence_penalty: nil
      )
    end

    it "does not warn when unsupported parameters are not provided" do
      expect(provider).not_to receive(:log_warn)

      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-4o"
      )
    end
  end

  describe "parameter filtering" do
    it "does not include unsupported parameters in the API request body" do
      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-4o",
        frequency_penalty: 0.5,
        presence_penalty: 0.3,
        best_of: 3,
        logit_bias: { "50256" => -100 }
      )

      # Check the request body sent to the API
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with { |req|
          body = JSON.parse(req.body)
          # Verify unsupported params are NOT present
          !body.key?("frequency_penalty") &&
            !body.key?("presence_penalty") &&
            !body.key?("best_of") &&
            !body.key?("logit_bias")
        }
    end

    it "includes supported parameters in the API request body" do
      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-4o",
        temperature: 0.7,
        top_p: 0.9,
        max_tokens: 100,
        frequency_penalty: 0.5  # This should be filtered out
      )

      # Check the request body sent to the API
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with { |req|
          body = JSON.parse(req.body)
          # Verify supported params ARE present
          body["temperature"] == 0.7 &&
            body["top_p"] == 0.9 &&
            body["max_output_tokens"] == 100 &&
            # Verify unsupported param is NOT present
            !body.key?("frequency_penalty")
        }
    end
  end

  describe "removed continuation marker parameters" do
    it "ignores continuation_marker parameter (passed to **kwargs but not used)" do
      # Parameter is accepted by **kwargs but has no effect
      # The key verification is that the implementation doesn't use it
      expect {
        provider.responses_completion(
          messages: [{ role: "user", content: "Test" }],
          model: "gpt-4o",
          continuation_marker: "<<<CUSTOM>>>"
        )
      }.not_to raise_error
    end

    it "ignores detect_natural_markers parameter (passed to **kwargs but not used)" do
      # Parameter is accepted by **kwargs but has no effect
      # The key verification is that the implementation doesn't use it
      expect {
        provider.responses_completion(
          messages: [{ role: "user", content: "Test" }],
          model: "gpt-4o",
          detect_natural_markers: false
        )
      }.not_to raise_error
    end

    it "does not have detect_continuation_marker private method" do
      expect(provider.private_methods).not_to include(:detect_continuation_marker)
    end

    it "does not have strip_continuation_markers private method" do
      expect(provider.private_methods).not_to include(:strip_continuation_markers)
    end
  end

  describe "reasoning model parameter filtering" do
    it "warns about temperature for reasoning models" do
      expect(provider).to receive(:log_warn).with(
        "⚠️ Parameter 'temperature' is not supported by reasoning model gpt-5-nano",
        hash_including(
          parameter: :temperature,
          value: 0.7,
          model: "gpt-5-nano",
          suggestion: "Remove this parameter - reasoning models (GPT-5, o1) only support default settings"
        )
      )

      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-5-nano",
        temperature: 0.7
      )
    end

    it "warns about top_p for reasoning models" do
      expect(provider).to receive(:log_warn).with(
        "⚠️ Parameter 'top_p' is not supported by reasoning model gpt-5",
        hash_including(
          parameter: :top_p,
          value: 0.9,
          model: "gpt-5",
          suggestion: "Remove this parameter - reasoning models (GPT-5, o1) only support default settings"
        )
      )

      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-5",
        top_p: 0.9
      )
    end

    it "does not include temperature or top_p in API request for reasoning models" do
      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-5-nano",
        temperature: 0.7,
        top_p: 0.9
      )

      # Check the request body sent to the API
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with { |req|
          body = JSON.parse(req.body)
          # Verify temperature and top_p are NOT present for reasoning models
          !body.key?("temperature") && !body.key?("top_p")
        }
    end

    it "includes temperature and top_p for non-reasoning models" do
      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "gpt-4o",
        temperature: 0.7,
        top_p: 0.9
      )

      # Check the request body sent to the API
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with { |req|
          body = JSON.parse(req.body)
          # Verify temperature and top_p ARE present for non-reasoning models
          body["temperature"] == 0.7 && body["top_p"] == 0.9
        }
    end

    it "warns about all unsupported parameters for o1-preview model" do
      expect(provider).to receive(:log_warn).with(
        "⚠️ Parameter 'temperature' is not supported by reasoning model o1-preview",
        hash_including(parameter: :temperature, model: "o1-preview")
      )
      expect(provider).to receive(:log_warn).with(
        "⚠️ Parameter 'frequency_penalty' is not supported by reasoning model o1-preview",
        hash_including(parameter: :frequency_penalty, model: "o1-preview")
      )

      provider.responses_completion(
        messages: [{ role: "user", content: "Hello" }],
        model: "o1-preview",
        temperature: 0.7,
        frequency_penalty: 0.5
      )
    end
  end

  describe "no continuation protocol injection" do
    it "does not inject continuation protocol into system instructions" do
      # Capture the request body to verify instructions
      request_body = nil
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return do |request|
          request_body = JSON.parse(request.body)
          {
            status: 200,
            body: {
              id: "resp_test123",
              status: "completed",
              output: [
                {
                  type: "message",
                  role: "assistant",
                  content: [{ type: "output_text", text: "Test response" }]
                }
              ],
              usage: { input_tokens: 10, output_tokens: 15, total_tokens: 25 }
            }.to_json
          }
        end

      provider.responses_completion(
        messages: [
          { role: "system", content: "You are a helpful assistant" },
          { role: "user", content: "Hello" }
        ],
        model: "gpt-4o",
        auto_continuation: true
      )

      # Verify instructions do NOT contain continuation protocol text
      instructions = request_body["instructions"]
      expect(instructions).not_to be_nil
      expect(instructions).not_to include("CONTINUATION PROTOCOL")
      expect(instructions).not_to include("<<<CONTINUE>>>")
      expect(instructions).to eq("You are a helpful assistant")
    end
  end
end
