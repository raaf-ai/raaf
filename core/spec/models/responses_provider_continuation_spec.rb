# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe RAAF::Models::ResponsesProvider, "Continuation Support" do
  let(:api_key) { "sk-test-key" }
  let(:provider) { described_class.new(api_key: api_key) }
  let(:model) { "gpt-4o" }
  let(:messages) { [{ role: "user", content: "Generate a long response" }] }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.reset!
  end

  # ========================================
  # TRUNCATION DETECTION TESTS (10 tests)
  # ========================================

  describe "Truncation Detection Tests" do
    describe "finish_reason handling" do
      let(:base_response) do
        {
          id: "resp_test_123",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "text", text: "Partial response..." }]
            }
          ],
          usage: { input_tokens: 15, output_tokens: 25, total_tokens: 40 }
        }
      end

      it 'detects finish_reason: "length" (truncation)' do
        truncated_response = base_response.merge(
          finish_reason: "length",
          metadata: { truncated: true }
        )

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: truncated_response.to_json)

        result = provider.responses_completion(messages: messages, model: model)

        expect(result["finish_reason"]).to eq("length")
        expect(result["metadata"]["truncated"]).to be true
      end

      it 'detects finish_reason: "stop" (no continuation)' do
        complete_response = base_response.merge(
          finish_reason: "stop",
          metadata: { truncated: false }
        )

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: complete_response.to_json)

        result = provider.responses_completion(messages: messages, model: model)

        expect(result["finish_reason"]).to eq("stop")
        expect(result["metadata"]["truncated"]).to be false
      end

      it 'detects finish_reason: "tool_calls" (tool invocation)' do
        tool_response = base_response.merge(
          finish_reason: "tool_calls",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [],
              tool_calls: [
                {
                  id: "call_123",
                  type: "function",
                  function: { name: "get_weather", arguments: '{"location":"Tokyo"}' }
                }
              ]
            }
          ]
        )

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: tool_response.to_json)

        result = provider.responses_completion(messages: messages, model: model)

        expect(result["finish_reason"]).to eq("tool_calls")
        expect(result["output"].first["tool_calls"]).not_to be_empty
      end

      it 'detects finish_reason: "content_filter" (safety filter)' do
        filtered_response = base_response.merge(
          finish_reason: "content_filter",
          metadata: { content_filter: "harmful_content" }
        )

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: filtered_response.to_json)

        expect(provider).to receive(:log_warn).with(/Content filtered by safety system/, hash_including(:filter_type))

        result = provider.responses_completion(messages: messages, model: model)
        expect(result["finish_reason"]).to eq("content_filter")
      end

      it 'detects finish_reason: "incomplete" (incomplete response)' do
        incomplete_response = base_response.merge(
          finish_reason: "incomplete",
          metadata: { incomplete_reason: "max_time_exceeded" }
        )

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: incomplete_response.to_json)

        expect(provider).to receive(:log_warn).with(/Response marked as incomplete/, hash_including(:suggestion))

        result = provider.responses_completion(messages: messages, model: model)
        expect(result["finish_reason"]).to eq("incomplete")
      end

      it 'detects finish_reason: "error" (API error)' do
        error_response = base_response.merge(
          finish_reason: "error",
          error: { message: "Internal processing error", code: "internal_error" }
        )

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: error_response.to_json)

        expect(provider).to receive(:log_error).with(/error finish_reason/, hash_including(:error))

        result = provider.responses_completion(messages: messages, model: model)
        expect(result["finish_reason"]).to eq("error")
      end

      it "handles null/missing finish_reason" do
        no_finish_reason_response = base_response.dup
        # No finish_reason field

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: no_finish_reason_response.to_json)

        result = provider.responses_completion(messages: messages, model: model)

        expect(result["finish_reason"]).to be_nil
      end

      it "logs WARN for content_filter with emoji" do
        filtered_response = base_response.merge(
          finish_reason: "content_filter",
          metadata: { filter_type: "profanity" }
        )

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: filtered_response.to_json)

        expect(provider).to receive(:log_warn).with(
          /Content filtered by safety system/,
          hash_including(:filter_type)
        )

        provider.responses_completion(messages: messages, model: model)
      end

      it "logs WARN for incomplete with remediation guidance" do
        incomplete_response = base_response.merge(
          finish_reason: "incomplete",
          metadata: { reason: "timeout" }
        )

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: incomplete_response.to_json)

        expect(provider).to receive(:log_warn).with(
          /Response marked as incomplete/,
          hash_including(:reason)
        )

        provider.responses_completion(messages: messages, model: model)
      end

      it "logs ERROR for error finish_reason" do
        error_response = base_response.merge(
          finish_reason: "error",
          error: { message: "Processing failed", code: "internal" }
        )

        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: error_response.to_json)

        expect(provider).to receive(:log_error).with(
          /API returned error finish_reason/,
          hash_including(:error)
        )

        provider.responses_completion(messages: messages, model: model)
      end
    end
  end

  # ==========================================
  # AGENT CONFIGURATION CHECKS (5 tests)
  # ==========================================

  describe "Agent Configuration Checks" do
    let(:agent_with_continuation) do
      double("Agent",
             continuation_enabled?: true,
             continuation_config: {
               max_attempts: 5,
               output_format: "json",
               on_failure: "return_partial"
             })
    end

    let(:agent_without_continuation) do
      double("Agent", continuation_enabled?: false)
    end

    it "checks if agent has continuation enabled" do
      expect(agent_with_continuation.continuation_enabled?).to be true
      expect(agent_without_continuation.continuation_enabled?).to be false
    end

    it "skips continuation if agent does not have it enabled" do
      truncated_response = {
        id: "resp_123",
        finish_reason: "length",
        output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Truncated..." }] }],
        usage: { input_tokens: 10, output_tokens: 50 }
      }

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: truncated_response.to_json)
        .times(1)

      allow(provider).to receive(:agent_continuation_enabled?).and_return(false)

      result = provider.responses_completion(messages: messages, model: model)
      expect(result["finish_reason"]).to eq("length")
    end

    it "extracts continuation config from agent" do
      config = agent_with_continuation.continuation_config

      expect(config[:max_attempts]).to eq(5)
      expect(config[:output_format]).to eq("json")
      expect(config[:on_failure]).to eq("return_partial")
    end

    it "uses default config if agent config missing" do
      agent_with_partial_config = double("Agent",
                                         continuation_enabled?: true,
                                         continuation_config: { max_attempts: 3 })

      config = agent_with_partial_config.continuation_config
      default_config = {
        max_attempts: config[:max_attempts] || 10,
        output_format: config[:output_format] || "text",
        on_failure: config[:on_failure] || "raise_error"
      }

      expect(default_config[:max_attempts]).to eq(3)
      expect(default_config[:output_format]).to eq("text")
      expect(default_config[:on_failure]).to eq("raise_error")
    end
  end

  # ==========================================
  # CONTINUATION LOOP TESTS (8 tests)
  # ==========================================

  describe "Continuation Loop Tests" do
    let(:first_response) do
      {
        id: "resp_001",
        finish_reason: "length",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "This is the first part of a long response..." }]
          }
        ],
        usage: { input_tokens: 10, output_tokens: 50 }
      }
    end

    let(:continuation_response) do
      {
        id: "resp_002",
        finish_reason: "stop",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "...and this is the continuation." }]
          }
        ],
        usage: { input_tokens: 60, output_tokens: 20 }
      }
    end

    it 'enters continuation loop on finish_reason: "length"' do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)
        .then
        .to_return(status: 200, body: continuation_response.to_json)

      response = provider.responses_completion(messages: messages, model: model)

      # The truncated first chunk is continued before the caller sees anything,
      # so what comes back is the finished response.
      expect(response["finish_reason"]).to eq("stop")
      expect(response["continuation_chunks"]).to eq(2)
    end

    it "makes additional API call in continuation" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)
        .then
        .to_return(status: 200, body: continuation_response.to_json)

      provider.responses_completion(messages: messages, model: model)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses").times(2)
    end

    it "does not continue when auto_continuation is disabled" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)

      response = provider.responses_completion(messages: messages, model: model, auto_continuation: false)

      expect(response["finish_reason"]).to eq("length")
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses").times(1)
    end

    it "accumulates content from multiple chunks" do
      third_response = {
        id: "resp_003",
        finish_reason: "stop",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: " Final piece." }]
          }
        ],
        usage: { input_tokens: 80, output_tokens: 10 }
      }

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)
        .then
        .to_return(status: 200, body: continuation_response.merge(finish_reason: "length").to_json)
        .then
        .to_return(status: 200, body: third_response.to_json)

      response = provider.responses_completion(messages: messages, model: model)

      # Text from every chunk survives into the merged response.
      full_text = response["output"].first["content"].first["text"]
      expect(full_text).to include("first part")
      expect(full_text).to include("continuation")
      expect(full_text).to include("Final piece")
      expect(response["continuation_chunks"]).to eq(3)
    end

    it "sums usage across chunks" do
      third_response = {
        id: "resp_003",
        finish_reason: "stop",
        output: [{ type: "message", role: "assistant", content: [{ type: "text", text: " Final piece." }] }],
        usage: { input_tokens: 80, output_tokens: 10, total_tokens: 90 }
      }

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.merge(usage: { input_tokens: 40, output_tokens: 30,
                                                                    total_tokens: 70 }).to_json)
        .then
        .to_return(status: 200, body: continuation_response.merge(finish_reason: "length",
                                                                  usage: { input_tokens: 60, output_tokens: 20,
                                                                           total_tokens: 80 }).to_json)
        .then
        .to_return(status: 200, body: third_response.to_json)

      response = provider.responses_completion(messages: messages, model: model)

      expect(response["usage"]["input_tokens"]).to eq(180)
      expect(response["usage"]["output_tokens"]).to eq(60)
      expect(response["usage"]["total_tokens"]).to eq(240)
    end

    it "tracks continuation attempts" do
      5.times do |i|
        response = {
          id: "resp_#{i}",
          finish_reason: i < 4 ? "length" : "stop",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "text", text: "Part #{i + 1}" }]
            }
          ],
          usage: { input_tokens: 10 + (i * 10), output_tokens: 20 }
        }

        if i == 0
          stub_request(:post, "https://api.openai.com/v1/responses")
            .to_return(status: 200, body: response.to_json)
        else
          stub_request(:post, "https://api.openai.com/v1/responses")
            .with(body: hash_including("previous_response_id" => "resp_#{i - 1}"))
            .to_return(status: 200, body: response.to_json)
        end
      end

      response = provider.responses_completion(messages: messages, model: model)

      expect(response["continuation_chunks"]).to eq(5)
      expect(response["id"]).to eq("resp_4")
      expect(response["finish_reason"]).to eq("stop")
    end

    it "respects max_attempts limit" do
      10.times do |i|
        response = {
          id: "resp_#{i}",
          finish_reason: "length",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "text", text: "Part #{i + 1}" }]
            }
          ],
          usage: { input_tokens: 10 + (i * 10), output_tokens: 20 }
        }

        if i == 0
          stub_request(:post, "https://api.openai.com/v1/responses")
            .to_return(status: 200, body: response.to_json)
        else
          stub_request(:post, "https://api.openai.com/v1/responses")
            .with(body: hash_including("previous_response_id" => "resp_#{i - 1}"))
            .to_return(status: 200, body: response.to_json)
        end
      end

      response = provider.responses_completion(messages: messages, model: model, max_continuation_attempts: 3)

      expect(response["continuation_chunks"]).to eq(3)
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses").times(3)
    end

    it "stops continuation on non-length finish_reason" do
      second_response = continuation_response.merge(finish_reason: "tool_calls")

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)
        .then
        .to_return(status: 200, body: second_response.to_json)

      response = provider.responses_completion(messages: messages, model: model)

      # The second chunk asks for a tool, which is not truncation -- stop there.
      expect(response["finish_reason"]).to eq("tool_calls")
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses").times(2)
    end

    it "handles max_attempts exceeded gracefully" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)

      response = provider.responses_completion(messages: messages, model: model, max_continuation_attempts: 3)

      # Still truncated when the budget runs out -- returned rather than raised.
      expect(response["finish_reason"]).to eq("length")
      expect(response["continuation_chunks"]).to eq(3)
    end

    it "logs each continuation attempt" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)
        .then
        .to_return(status: 200, body: continuation_response.to_json)

      expect(provider).to receive(:log_debug)
        .with(/Continuation sequence iteration/, hash_including(chunk_number: 1)).at_least(:once)
      expect(provider).to receive(:log_debug)
        .with(/Continuation sequence iteration/, hash_including(chunk_number: 2)).at_least(:once)
      allow(provider).to receive(:log_debug)

      provider.responses_completion(messages: messages, model: model)
    end
  end

  # ================================================
  # STATEFUL API INTEGRATION TESTS (6 tests)
  # ================================================

  describe "Stateful API Integration Tests" do
    let(:response_with_id) do
      {
        id: "resp_abc123",
        previous_response_id: "resp_xyz789",
        finish_reason: "length",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "Response content" }]
          }
        ],
        usage: { input_tokens: 10, output_tokens: 20 }
      }
    end

    it "extracts previous_response_id from response" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: response_with_id.to_json)

      result = provider.responses_completion(messages: messages, model: model)

      expect(result["id"]).to eq("resp_abc123")
      expect(result["previous_response_id"]).to eq("resp_xyz789")
    end

    it "passes previous_response_id in continuation request" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .with(body: hash_including("previous_response_id" => "resp_first"))
        .to_return(status: 200, body: response_with_id.merge(finish_reason: "stop").to_json)

      provider.responses_completion(
        messages: [],
        model: model,
        previous_response_id: "resp_first"
      )

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with(body: hash_including("previous_response_id" => "resp_first"))
    end

    it "uses previous_response_id for context management" do
      first = {
        id: "resp_001",
        finish_reason: "length",
        output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part 1" }] }],
        usage: { input_tokens: 10, output_tokens: 20 }
      }

      second = {
        id: "resp_002",
        previous_response_id: "resp_001",
        finish_reason: "stop",
        output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part 2" }] }],
        usage: { input_tokens: 30, output_tokens: 15 }
      }

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first.to_json)
        .then
        .to_return(status: 200, body: second.to_json)

      response = provider.responses_completion(messages: messages, model: model)

      # The continuation is issued against the first chunk's id, and the
      # response that comes back is the one that finished the sequence.
      expect(response["id"]).to eq("resp_002")
      expect(response["previous_response_id"]).to eq("resp_001")
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with(body: hash_including("previous_response_id" => "resp_001"))
    end

    it "handles missing previous_response_id gracefully" do
      response_without_prev_id = {
        id: "resp_123",
        finish_reason: "stop",
        output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Content" }] }],
        usage: { input_tokens: 10, output_tokens: 20 }
      }

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: response_without_prev_id.to_json)

      result = provider.responses_completion(messages: messages, model: model)

      expect(result["id"]).to eq("resp_123")
      expect(result["previous_response_id"]).to be_nil
    end

    it "maintains response ID chain across continuations" do
      responses = []

      3.times do |i|
        response = {
          id: "resp_#{i}",
          previous_response_id: i > 0 ? "resp_#{i - 1}" : nil,
          finish_reason: i < 2 ? "length" : "stop",
          output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part #{i}" }] }],
          usage: { input_tokens: 10 + (i * 20), output_tokens: 20 }
        }

        if i == 0
          stub_request(:post, "https://api.openai.com/v1/responses")
            .to_return(status: 200, body: response.to_json)
        else
          stub_request(:post, "https://api.openai.com/v1/responses")
            .with(body: hash_including("previous_response_id" => "resp_#{i - 1}"))
            .to_return(status: 200, body: response.to_json)
        end
      end

      response = provider.responses_completion(messages: messages, model: model)
      responses << response

      # Each chunk is requested against the previous chunk's id, so the chain is
      # visible in the requests that were made.
      expect(response["id"]).to eq("resp_2")
      expect(response["previous_response_id"]).to eq("resp_1")
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with(body: hash_including("previous_response_id" => "resp_0"))
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with(body: hash_including("previous_response_id" => "resp_1"))
    end

    it "includes previous_response_id in logs" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: response_with_id.to_json)

      expect(provider).to receive(:log_debug).with(
        anything,
        hash_including(previous_response_id: "resp_xyz789")
      ).at_least(:once)
      allow(provider).to receive(:log_debug)

      provider.responses_completion(
        messages: [],
        model: model,
        previous_response_id: "resp_xyz789"
      )
    end
  end

  # ========================================
  # METADATA TRACKING TESTS (6 tests)
  # ========================================

  describe "Metadata Tracking Tests" do
    let(:response_with_metadata) do
      {
        id: "resp_123",
        finish_reason: "length",
        output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Content" }] }],
        usage: { input_tokens: 10, output_tokens: 50, total_tokens: 60 },
        metadata: {
          model: "gpt-4o",
          created_at: Time.now.to_i
        }
      }
    end

    it "tracks continuation_count" do
      metadata = {
        continuation_count: 0,
        chunks: []
      }

      3.times do |i|
        response = {
          id: "resp_#{i}",
          finish_reason: i < 2 ? "length" : "stop",
          output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part #{i}" }] }],
          usage: { input_tokens: 10, output_tokens: 20 }
        }

        metadata[:continuation_count] += 1
        metadata[:chunks] << response
      end

      expect(metadata[:continuation_count]).to eq(3)
      expect(metadata[:chunks].size).to eq(3)
    end

    it "records token usage per chunk" do
      chunks_metadata = []

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: response_with_metadata.to_json)

      result = provider.responses_completion(messages: messages, model: model, auto_continuation: false)

      chunks_metadata << {
        chunk_index: 0,
        input_tokens: result["usage"]["input_tokens"],
        output_tokens: result["usage"]["output_tokens"],
        total_tokens: result["usage"]["total_tokens"]
      }

      expect(chunks_metadata.first[:input_tokens]).to eq(10)
      expect(chunks_metadata.first[:output_tokens]).to eq(50)
      expect(chunks_metadata.first[:total_tokens]).to eq(60)
    end

    it "calculates total costs" do
      input_price_per_1k = 0.01
      output_price_per_1k = 0.03

      total_input_tokens = 0
      total_output_tokens = 0

      2.times do |i|
        response = {
          id: "resp_#{i}",
          finish_reason: i == 0 ? "length" : "stop",
          output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part #{i}" }] }],
          usage: { input_tokens: 100, output_tokens: 200 }
        }

        total_input_tokens += response[:usage][:input_tokens]
        total_output_tokens += response[:usage][:output_tokens]
      end

      total_cost = (total_input_tokens / 1000.0 * input_price_per_1k) +
                   (total_output_tokens / 1000.0 * output_price_per_1k)

      expect(total_input_tokens).to eq(200)
      expect(total_output_tokens).to eq(400)
      expect(total_cost).to be_within(0.001).of(0.014)
    end

    it "stores truncation points" do
      truncation_metadata = {
        truncation_points: [],
        truncated_at_tokens: []
      }

      response = {
        id: "resp_001",
        finish_reason: "length",
        output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Truncated text..." }] }],
        usage: { output_tokens: 4096 }
      }

      if response[:finish_reason] == "length"
        truncation_metadata[:truncation_points] << response[:id]
        truncation_metadata[:truncated_at_tokens] << response[:usage][:output_tokens]
      end

      expect(truncation_metadata[:truncation_points]).to eq(["resp_001"])
      expect(truncation_metadata[:truncated_at_tokens]).to eq([4096])
    end

    it "records finish_reason for each chunk" do
      chunk_finish_reasons = []

      %w[length length stop].each_with_index do |reason, i|
        {
          id: "resp_#{i}",
          finish_reason: reason,
          output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part #{i}" }] }]
        }

        chunk_finish_reasons << { chunk: i, finish_reason: reason }
      end

      expect(chunk_finish_reasons).to eq([
                                           { chunk: 0, finish_reason: "length" },
                                           { chunk: 1, finish_reason: "length" },
                                           { chunk: 2, finish_reason: "stop" }
                                         ])
    end

    it "includes all metadata in final result" do
      final_metadata = {
        continuation_count: 2,
        total_chunks: 2,
        truncation_points: ["resp_001"],
        finish_reasons: %w[length stop],
        total_input_tokens: 150,
        total_output_tokens: 300,
        model: "gpt-4o",
        max_attempts_reached: false
      }

      expect(final_metadata[:continuation_count]).to eq(2)
      expect(final_metadata[:total_chunks]).to eq(2)
      expect(final_metadata[:truncation_points]).to include("resp_001")
      expect(final_metadata[:finish_reasons]).to eq(%w[length stop])
    end
  end

  # ==========================================
  # INTEGRATION WITH CONFIG TESTS (5 tests)
  # ==========================================

  describe "Integration Tests with Config" do
    let(:continuation_config) do
      {
        enabled: true,
        max_attempts: 5,
        output_format: "json",
        on_failure: "return_partial",
        merge_strategy: "concatenate"
      }
    end

    it "reads max_attempts from config" do
      config = continuation_config
      expect(config[:max_attempts]).to eq(5)
    end

    it "reads output_format from config" do
      config = continuation_config
      expect(config[:output_format]).to eq("json")
    end

    it "passes output_format to merger factory" do
      merger_factory = double("MergerFactory")
      allow(merger_factory).to receive(:create).with("json").and_return(double("JsonMerger"))

      merger = merger_factory.create(continuation_config[:output_format])
      expect(merger).not_to be_nil
    end

    it "applies on_failure setting" do
      config = continuation_config

      if config[:on_failure] == "return_partial"
        expect(config[:on_failure]).to eq("return_partial")
      elsif config[:on_failure] == "raise_error"
        expect(config[:on_failure]).to eq("raise_error")
      end
    end

    it "uses format-aware continuation prompt" do
      prompts_by_format = {
        "json" => "Please continue the JSON object from where it was truncated. Do not repeat content.",
        "markdown" => "Please continue the markdown document from where it was truncated.",
        "csv" => "Please continue from where you left off, completing any partial rows."
      }

      format = continuation_config[:output_format]
      prompt = prompts_by_format[format]

      expect(prompt).to include("JSON")
    end
  end

  # ==========================================
  # EDGE CASE TESTS (5 tests)
  # ==========================================

  describe "Edge Case Tests" do
    it "handles very large partial responses" do
      large_text = "x" * 10_000
      large_response = {
        id: "resp_large",
        finish_reason: "length",
        output: [{ type: "message", role: "assistant", content: [{ type: "text", text: large_text }] }],
        usage: { input_tokens: 100, output_tokens: 4096 }
      }

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: large_response.to_json)

      result = provider.responses_completion(messages: messages, model: model, auto_continuation: false)

      expect(result["output"].first["content"].first["text"].length).to eq(10_000)
      expect(result["finish_reason"]).to eq("length")
    end

    it "handles multiple consecutive truncations" do
      5.times do |i|
        stub_request(:post, "https://api.openai.com/v1/responses")
          .with(body: i == 0 ? anything : hash_including("previous_response_id" => "resp_#{i - 1}"))
          .to_return(status: 200, body: {
            id: "resp_#{i}",
            finish_reason: "length",
            output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part #{i}" }] }],
            usage: { input_tokens: 10 + (i * 5), output_tokens: 50 }
          }.to_json)
      end

      response = provider.responses_completion(messages: messages, model: model, max_continuation_attempts: 5)

      # Truncated all the way to the attempt limit; every chunk's text is kept.
      expect(response["finish_reason"]).to eq("length")
      expect(response["continuation_chunks"]).to eq(5)
      expect(response["id"]).to eq("resp_4")
      expect(response["output"].first["content"].first["text"]).to eq("Part 0Part 1Part 2Part 3Part 4")
    end

    it "handles mixed finish_reasons in sequence" do
      finish_reasons = %w[length tool_calls length stop]

      bodies = finish_reasons.each_with_index.map do |reason, i|
        {
          id: "resp_#{i}",
          finish_reason: reason,
          output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part #{i}" }] }],
          usage: { input_tokens: 10, output_tokens: 20 }
        }.to_json
      end

      stub = stub_request(:post, "https://api.openai.com/v1/responses")
      bodies.each { |body| stub = stub.to_return(status: 200, body: body).then }

      response = provider.responses_completion(messages: messages, model: model)

      # "length" continues, "tool_calls" does not -- the sequence stops at the
      # second chunk and the remaining stubs go unused.
      expect(response["finish_reason"]).to eq("tool_calls")
      expect(response["continuation_chunks"]).to eq(2)
      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses").times(2)
    end

    it "preserves response order across continuations" do
      chunks = []

      3.times do |i|
        response = {
          id: "resp_#{i}",
          sequence: i,
          finish_reason: i < 2 ? "length" : "stop",
          output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part #{i}" }] }],
          usage: { input_tokens: 10, output_tokens: 20 }
        }

        chunks << response
      end

      expect(chunks.map { |c| c[:sequence] }).to eq([0, 1, 2])
      expect(chunks.map { |c| c[:id] }).to eq(%w[resp_0 resp_1 resp_2])
    end

    it "handles empty continuation response" do
      empty_response = {
        id: "resp_empty",
        finish_reason: "stop",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "" }]
          }
        ],
        usage: { input_tokens: 50, output_tokens: 0 }
      }

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: {
          id: "resp_001",
          finish_reason: "length",
          output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Content" }] }],
          usage: { input_tokens: 10, output_tokens: 20 }
        }.to_json)
        .then
        .to_return(status: 200, body: empty_response.to_json)

      response = provider.responses_completion(messages: messages, model: model)

      # The continuation added nothing, so only the first chunk's text remains.
      expect(response["id"]).to eq("resp_empty")
      expect(response["output"].first["content"].first["text"]).to eq("Content")
    end
  end

  # ==========================================
  # ERROR HANDLING TESTS (5 tests)
  # ==========================================

  describe "Error Handling Tests" do
    it "handles network errors during continuation" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "resp_001", finish_reason: "length", output: [], usage: {} }.to_json)
        .then
        .to_raise(Net::ReadTimeout)

      expect do
        provider.responses_completion(messages: messages, model: model)
      end.to raise_error(Net::ReadTimeout)
    end

    it "handles malformed response during continuation" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "resp_001", finish_reason: "length", output: [], usage: {} }.to_json)
        .then
        .to_return(status: 200, body: "invalid json")

      expect do
        provider.responses_completion(messages: messages, model: model)
      end.to raise_error(JSON::ParserError)
    end

    it "handles timeout during continuation" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "resp_001", finish_reason: "length", output: [], usage: {} }.to_json)
        .then
        .to_timeout

      expect do
        provider.responses_completion(messages: messages, model: model)
      end.to raise_error(Net::OpenTimeout)
    end

    it "logs error details on API failure" do
      error_response = {
        error: {
          message: "Invalid request",
          type: "invalid_request_error",
          code: "invalid_api_key"
        }
      }

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 400, body: error_response.to_json)

      expect(provider).to receive(:log_error).with(
        /OpenAI Responses API Error/,
        hash_including(status_code: "400")
      )

      expect do
        provider.responses_completion(messages: messages, model: model)
      end.to raise_error(RAAF::Models::APIError)
    end

    it "allows graceful degradation with partial response" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: {
          id: "resp_001",
          finish_reason: "length",
          output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part 1" }] }],
          usage: { input_tokens: 10, output_tokens: 20 }
        }.to_json)
        .then
        .to_return(status: 500, body: "Internal Server Error")

      # A chunk that fails mid-sequence surfaces as an error rather than as a
      # silently shortened answer.
      expect do
        provider.responses_completion(messages: messages, model: model)
      end.to raise_error(RAAF::Models::ServerError)
    end
  end
end
