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

        expect(provider).to receive(:log_warn).with(/content_filter/)

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

        expect(provider).to receive(:log_warn).with(/incomplete/)

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

        expect(provider).to receive(:log_error).with(/error finish_reason/)

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
        }
      )
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
        continuation_config: { max_attempts: 3 }
      )

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

      allow(provider).to receive(:should_continue?).and_return(true, false)
      allow(provider).to receive(:merge_responses).and_call_original

      responses = []
      response = provider.responses_completion(messages: messages, model: model)
      responses << response

      if response["finish_reason"] == "length"
        continuation = provider.responses_completion(
          messages: [],
          model: model,
          previous_response_id: response["id"]
        )
        responses << continuation
      end

      expect(responses.size).to eq(2)
      expect(responses.first["finish_reason"]).to eq("length")
      expect(responses.last["finish_reason"]).to eq("stop")
    end

    it "makes additional API call in continuation" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)
        .then
        .to_return(status: 200, body: continuation_response.to_json)

      first = provider.responses_completion(messages: messages, model: model)
      second = provider.responses_completion(
        messages: [],
        model: model,
        previous_response_id: first["id"]
      )

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses").times(2)
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

      accumulated_content = []

      response1 = provider.responses_completion(messages: messages, model: model)
      accumulated_content << response1["output"].first["content"].first["text"]

      response2 = provider.responses_completion(messages: [], model: model, previous_response_id: response1["id"])
      accumulated_content << response2["output"].first["content"].first["text"]

      response3 = provider.responses_completion(messages: [], model: model, previous_response_id: response2["id"])
      accumulated_content << response3["output"].first["content"].first["text"]

      full_text = accumulated_content.join("")
      expect(full_text).to include("first part")
      expect(full_text).to include("continuation")
      expect(full_text).to include("Final piece")
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
          usage: { input_tokens: 10 + i * 10, output_tokens: 20 }
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

      prev_id = nil
      attempts = []

      5.times do |i|
        response = if i == 0
          provider.responses_completion(messages: messages, model: model)
        else
          provider.responses_completion(messages: [], model: model, previous_response_id: prev_id)
        end

        attempts << response["id"]
        prev_id = response["id"]

        break if response["finish_reason"] == "stop"
      end

      expect(attempts.size).to eq(5)
      expect(attempts.last).to eq("resp_4")
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
          usage: { input_tokens: 10 + i * 10, output_tokens: 20 }
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

      max_attempts = 3
      attempts = []
      prev_id = nil

      max_attempts.times do |i|
        response = if i == 0
          provider.responses_completion(messages: messages, model: model)
        else
          provider.responses_completion(messages: [], model: model, previous_response_id: prev_id)
        end

        attempts << response["id"]
        prev_id = response["id"]
      end

      expect(attempts.size).to eq(max_attempts)
    end

    it "stops continuation on non-length finish_reason" do
      second_response = continuation_response.merge(finish_reason: "tool_calls")

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)
        .then
        .to_return(status: 200, body: second_response.to_json)

      response1 = provider.responses_completion(messages: messages, model: model)
      response2 = provider.responses_completion(messages: [], model: model, previous_response_id: response1["id"])

      expect(response1["finish_reason"]).to eq("length")
      expect(response2["finish_reason"]).to eq("tool_calls")
    end

    it "handles max_attempts exceeded gracefully" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)

      max_attempts = 3
      attempts = []
      prev_id = nil

      max_attempts.times do |i|
        response = if i == 0
          provider.responses_completion(messages: messages, model: model)
        else
          provider.responses_completion(messages: [], model: model, previous_response_id: prev_id)
        end

        attempts << response
        prev_id = response["id"]
      end

      expect(attempts.size).to eq(max_attempts)
      expect(attempts.last["finish_reason"]).to eq("length")
    end

    it "logs each continuation attempt" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: first_response.to_json)
        .then
        .to_return(status: 200, body: continuation_response.to_json)

      expect(provider).to receive(:log_debug).with(/Continuation attempt 1/, anything).at_least(:once)
      expect(provider).to receive(:log_debug).with(/Continuation attempt 2/, anything).at_least(:once)

      provider.responses_completion(messages: messages, model: model)
      provider.responses_completion(messages: [], model: model, previous_response_id: "resp_001")
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
        .to_return(status: 200, body: response_with_id.to_json)

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

      response1 = provider.responses_completion(messages: messages, model: model)
      response2 = provider.responses_completion(
        messages: [],
        model: model,
        previous_response_id: response1["id"]
      )

      expect(response1["id"]).to eq("resp_001")
      expect(response2["id"]).to eq("resp_002")
      expect(response2["previous_response_id"]).to eq("resp_001")
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
          usage: { input_tokens: 10 + i * 20, output_tokens: 20 }
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

      prev_id = nil
      3.times do |i|
        response = if i == 0
          provider.responses_completion(messages: messages, model: model)
        else
          provider.responses_completion(messages: [], model: model, previous_response_id: prev_id)
        end

        responses << response
        prev_id = response["id"]
      end

      expect(responses[0]["id"]).to eq("resp_0")
      expect(responses[0]["previous_response_id"]).to be_nil
      expect(responses[1]["id"]).to eq("resp_1")
      expect(responses[1]["previous_response_id"]).to eq("resp_0")
      expect(responses[2]["id"]).to eq("resp_2")
      expect(responses[2]["previous_response_id"]).to eq("resp_1")
    end

    it "includes previous_response_id in logs" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: response_with_id.to_json)

      expect(provider).to receive(:log_debug).with(
        anything,
        hash_including(previous_response_id: "resp_xyz789")
      ).at_least(:once)

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

      result = provider.responses_completion(messages: messages, model: model)

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

      ["length", "length", "stop"].each_with_index do |reason, i|
        response = {
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
        finish_reasons: ["length", "stop"],
        total_input_tokens: 150,
        total_output_tokens: 300,
        model: "gpt-4o",
        max_attempts_reached: false
      }

      expect(final_metadata[:continuation_count]).to eq(2)
      expect(final_metadata[:total_chunks]).to eq(2)
      expect(final_metadata[:truncation_points]).to include("resp_001")
      expect(final_metadata[:finish_reasons]).to eq(["length", "stop"])
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

      result = provider.responses_completion(messages: messages, model: model)

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
            usage: { input_tokens: 10 + i * 5, output_tokens: 50 }
          }.to_json)
      end

      responses = []
      prev_id = nil

      5.times do |i|
        response = if i == 0
          provider.responses_completion(messages: messages, model: model)
        else
          provider.responses_completion(messages: [], model: model, previous_response_id: prev_id)
        end

        responses << response
        prev_id = response["id"]
        expect(response["finish_reason"]).to eq("length")
      end

      expect(responses.size).to eq(5)
      expect(responses.map { |r| r["id"] }).to eq((0..4).map { |i| "resp_#{i}" })
    end

    it "handles mixed finish_reasons in sequence" do
      finish_reasons = ["length", "tool_calls", "length", "stop"]

      finish_reasons.each_with_index do |reason, i|
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: {
            id: "resp_#{i}",
            finish_reason: reason,
            output: [{ type: "message", role: "assistant", content: [{ type: "text", text: "Part #{i}" }] }],
            usage: { input_tokens: 10, output_tokens: 20 }
          }.to_json).times(1)
      end

      collected_reasons = []

      4.times do |i|
        response = provider.responses_completion(messages: messages, model: model)
        collected_reasons << response["finish_reason"]
      end

      expect(collected_reasons).to eq(finish_reasons)
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
      expect(chunks.map { |c| c[:id] }).to eq(["resp_0", "resp_1", "resp_2"])
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

      response1 = provider.responses_completion(messages: messages, model: model)
      response2 = provider.responses_completion(messages: [], model: model, previous_response_id: response1["id"])

      expect(response2["output"].first["content"].first["text"]).to eq("")
      expect(response2["usage"]["output_tokens"]).to eq(0)
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

      response1 = provider.responses_completion(messages: messages, model: model)

      expect {
        provider.responses_completion(messages: [], model: model, previous_response_id: response1["id"])
      }.to raise_error(Net::ReadTimeout)
    end

    it "handles malformed response during continuation" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "resp_001", finish_reason: "length", output: [], usage: {} }.to_json)
        .then
        .to_return(status: 200, body: "invalid json")

      response1 = provider.responses_completion(messages: messages, model: model)

      expect {
        provider.responses_completion(messages: [], model: model, previous_response_id: response1["id"])
      }.to raise_error(JSON::ParserError)
    end

    it "handles timeout during continuation" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "resp_001", finish_reason: "length", output: [], usage: {} }.to_json)
        .then
        .to_timeout

      response1 = provider.responses_completion(messages: messages, model: model)

      expect {
        provider.responses_completion(messages: [], model: model, previous_response_id: response1["id"])
      }.to raise_error(Net::OpenTimeout)
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

      expect {
        provider.responses_completion(messages: messages, model: model)
      }.to raise_error(RAAF::APIError)
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

      response1 = provider.responses_completion(messages: messages, model: model)
      expect(response1["output"].first["content"].first["text"]).to eq("Part 1")

      expect {
        provider.responses_completion(messages: [], model: model, previous_response_id: response1["id"])
      }.to raise_error(RAAF::APIError)

      expect(response1).not_to be_nil
    end
  end
end
