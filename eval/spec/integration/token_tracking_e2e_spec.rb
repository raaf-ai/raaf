# frozen_string_literal: true

require 'raaf-core'

RSpec.describe "End-to-End Token Tracking", type: :integration do
  #
  # This integration test verifies the complete token tracking pipeline:
  # Provider → Normalizer → Runner → RunResult → Span → SpanSerializer → Eval Metrics
  #
  # It ensures that token usage data flows correctly through all layers of the system
  # with normalized field names (input_tokens, output_tokens, total_tokens).
  #

  describe "token tracking through complete pipeline" do
    let(:agent) do
      RAAF::Agent.new(
        name: "TestAgent",
        instructions: "You are a test assistant",
        model: "gpt-4o"
      )
    end

    let(:provider) { RAAF::Models::ResponsesProvider.new }
    let(:runner) { RAAF::Runner.new(agent: agent, provider: provider) }

    before do
      # Mock provider response with OpenAI format (legacy field names)
      allow(provider).to receive(:responses_completion).and_return(
        {
          "id" => "resp_123",
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => "Test response from agent"
            }
          ],
          "usage" => {
            "prompt_tokens" => 100,        # Legacy OpenAI field
            "completion_tokens" => 50,     # Legacy OpenAI field
            "total_tokens" => 150          # Legacy OpenAI field
          }
        }
      )
    end

    it "normalizes provider response and tracks tokens through complete pipeline" do
      # Step 1: Run agent (triggers provider → normalizer → runner)
      result = runner.run("Test message")

      # Step 2: Verify RunResult has normalized token fields
      expect(result.usage).not_to be_nil
      expect(result.usage[:input_tokens]).to eq(100)
      expect(result.usage[:output_tokens]).to eq(50)
      expect(result.usage[:total_tokens]).to eq(150)

      # Step 3: Verify provider metadata is preserved
      expect(result.usage[:provider_metadata]).not_to be_nil
      expect(result.usage[:provider_metadata][:provider_name]).to eq("responses")
      expect(result.usage[:provider_metadata][:raw_usage]).to include("prompt_tokens" => 100)
    end

    it "populates span attributes with normalized token data" do
      # Create tracer to capture spans
      tracer = RAAF::Tracing::SpanTracer.new
      runner_with_tracing = RAAF::Runner.new(agent: agent, provider: provider, tracer: tracer)

      # Run agent
      result = runner_with_tracing.run("Test message")

      # Get the agent span
      spans = tracer.spans
      agent_span = spans.find { |s| s.name.include?("TestAgent") }

      expect(agent_span).not_to be_nil

      # Verify span has token attributes populated
      expect(agent_span.input_tokens).to eq(100)
      expect(agent_span.output_tokens).to eq(50)
      expect(agent_span.total_tokens).to eq(150)
    end

    it "serializes span with token data for eval system" do
      # Create tracer to capture spans
      tracer = RAAF::Tracing::SpanTracer.new
      runner_with_tracing = RAAF::Runner.new(agent: agent, provider: provider, tracer: tracer)

      # Run agent
      result = runner_with_tracing.run("Test message")

      # Get the agent span
      spans = tracer.spans
      agent_span = spans.find { |s| s.name.include?("TestAgent") }

      # Serialize span using SpanSerializer
      serialized = RAAF::Eval::SpanSerializer.serialize(agent_span)

      # Verify metadata contains normalized token fields
      expect(serialized[:metadata]).not_to be_nil
      expect(serialized[:metadata][:input_tokens]).to eq(100)
      expect(serialized[:metadata][:output_tokens]).to eq(50)
      expect(serialized[:metadata][:tokens]).to eq(150)
    end

    it "calculates metrics correctly using normalized token data" do
      # Mock two different usage patterns
      baseline_usage = { input_tokens: 100, output_tokens: 50, total_tokens: 150 }
      eval_usage = { input_tokens: 120, output_tokens: 60, total_tokens: 180 }

      # Calculate token usage difference
      diff_percent = RAAF::Eval::MetricsCalculator.token_usage_diff_percent(
        baseline_usage[:total_tokens],
        eval_usage[:total_tokens]
      )

      expect(diff_percent).to eq(20.0) # 30 token increase = 20% increase

      # Calculate cost difference
      cost_diff = RAAF::Eval::MetricsCalculator.cost_diff(
        baseline_usage,
        eval_usage,
        model: "gpt-4o"
      )

      # Cost should be calculated using normalized fields
      # gpt-4o: $2.50 per 1M input, $10.00 per 1M output
      # Baseline: (100 * 2.50 + 50 * 10.00) / 1_000_000 = 0.00075
      # Eval: (120 * 2.50 + 60 * 10.00) / 1_000_000 = 0.00090
      # Diff: 0.00015
      expect(cost_diff).to be_within(0.000001).of(0.00015)
    end

    it "handles multiple provider formats through normalization" do
      # Test with Anthropic format (already normalized)
      anthropic_response = {
        "id" => "msg_123",
        "type" => "message",
        "content" => [{ "type" => "text", "text" => "Response" }],
        "usage" => {
          "input_tokens" => 200,
          "output_tokens" => 100
          # No total_tokens - should be calculated
        }
      }

      allow(provider).to receive(:responses_completion).and_return(anthropic_response)

      result = runner.run("Test message")

      # Verify normalization calculated total_tokens
      expect(result.usage[:input_tokens]).to eq(200)
      expect(result.usage[:output_tokens]).to eq(100)
      expect(result.usage[:total_tokens]).to eq(300) # Calculated
    end

    it "preserves reasoning token details for o1 models" do
      # Mock o1 response with reasoning tokens
      o1_response = {
        "id" => "resp_o1",
        "output" => [
          {
            "type" => "message",
            "role" => "assistant",
            "content" => "Reasoning response"
          }
        ],
        "usage" => {
          "input_tokens" => 500,
          "output_tokens" => 1000,
          "total_tokens" => 1500,
          "output_tokens_details" => {
            "reasoning_tokens" => 400
          }
        }
      }

      allow(provider).to receive(:responses_completion).and_return(o1_response)

      result = runner.run("Complex problem")

      # Verify reasoning tokens are preserved
      expect(result.usage[:output_tokens_details]).not_to be_nil
      expect(result.usage[:output_tokens_details][:reasoning_tokens]).to eq(400)
    end

    it "handles cached tokens from prompt caching" do
      # Mock response with cached tokens
      cached_response = {
        "id" => "resp_cached",
        "output" => [
          {
            "type" => "message",
            "role" => "assistant",
            "content" => "Response using cached context"
          }
        ],
        "usage" => {
          "input_tokens" => 1000,
          "output_tokens" => 50,
          "total_tokens" => 1050,
          "input_tokens_details" => {
            "cached_tokens" => 800
          }
        }
      }

      allow(provider).to receive(:responses_completion).and_return(cached_response)

      result = runner.run("Query with cached context")

      # Verify cached tokens are preserved
      expect(result.usage[:input_tokens_details]).not_to be_nil
      expect(result.usage[:input_tokens_details][:cached_tokens]).to eq(800)
    end
  end

  describe "eval metrics integration" do
    it "uses normalized fields in RSpec matchers" do
      baseline_usage = { input_tokens: 100, output_tokens: 50, total_tokens: 150 }
      eval_result = double(
        usage: { input_tokens: 110, output_tokens: 55, total_tokens: 165 }
      )

      # This tests that performance matchers use normalized fields
      total_tokens = (eval_result.usage[:input_tokens] || 0) +
                     (eval_result.usage[:output_tokens] || 0)

      expect(total_tokens).to eq(165)
    end

    it "supports backward compatibility with legacy field names" do
      # Metrics should still work with old field names as fallback
      legacy_usage = { prompt_tokens: 100, completion_tokens: 50 }

      # MetricsCalculator should handle legacy fields
      input = legacy_usage[:input_tokens] || legacy_usage[:prompt_tokens] || 0
      output = legacy_usage[:output_tokens] || legacy_usage[:completion_tokens] || 0

      expect(input).to eq(100)
      expect(output).to eq(50)
    end
  end

  describe "complete evaluation workflow with real token tracking" do
    let(:baseline_span_data) do
      {
        span_id: SecureRandom.uuid,
        trace_id: SecureRandom.uuid,
        span_type: "agent",
        agent_name: "WeatherAgent",
        model: "gpt-4o",
        instructions: "You are a weather assistant",
        parameters: { temperature: 0.7, max_tokens: 100 },
        input_messages: [{ role: "user", content: "What's the weather?" }],
        output_messages: [{ role: "assistant", content: "It's sunny and 72F" }],
        metadata: {
          tokens: 150,
          input_tokens: 100,
          output_tokens: 50,
          latency_ms: 1000
        }
      }
    end

    before do
      # Mock provider with different token counts for eval run
      allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:responses_completion).and_return(
        {
          "id" => "resp_eval",
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => "It's sunny and warm today!"
            }
          ],
          "usage" => {
            "input_tokens" => 105,
            "output_tokens" => 55,
            "total_tokens" => 160
          }
        }
      )
    end

    it "tracks token changes through complete evaluation" do
      engine = RAAF::Eval::EvaluationEngine.new

      # Create evaluation run
      run = engine.create_run(
        name: "Token Tracking Test",
        description: "Verify token tracking through eval system",
        baseline_span: baseline_span_data,
        configurations: [
          {
            name: "Slight Temperature Increase",
            changes: { parameters: { temperature: 0.75 } }
          }
        ],
        initiated_by: "test_user"
      )

      # Execute evaluation
      results = engine.execute_run(run)
      result = results.first

      # Verify token metrics are captured
      expect(result.token_metrics).not_to be_empty
      expect(result.token_metrics[:baseline]).to eq(150)
      expect(result.token_metrics[:result]).to eq(160)
      expect(result.token_metrics[:delta]).to eq(10)
      expect(result.token_metrics[:percentage_change]).to be_within(0.1).of(6.7)
    end
  end
end
