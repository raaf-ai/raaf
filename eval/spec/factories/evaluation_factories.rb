# frozen_string_literal: true

FactoryBot.define do
  factory :evaluation_run, class: 'RAAF::Eval::Models::EvaluationRun' do
    name { "Test Evaluation #{SecureRandom.hex(4)}" }
    description { "Testing agent behavior changes" }
    status { "pending" }
    baseline_span_id { SecureRandom.uuid }
    initiated_by { "test_user" }
    metadata { { tags: ["test"], version: "1.0" } }
  end

  factory :evaluation_span, class: 'RAAF::Eval::Models::EvaluationSpan' do
    span_id { SecureRandom.uuid }
    trace_id { SecureRandom.uuid }
    span_type { "agent" }
    source { "production_trace" }
    span_data do
      {
        agent_name: "TestAgent",
        model: "gpt-4o",
        instructions: "You are a test assistant",
        parameters: { temperature: 0.7 },
        input_messages: [{ role: "user", content: "Hello" }],
        output_messages: [{ role: "assistant", content: "Hi there!" }],
        metadata: { tokens: 50, input_tokens: 10, output_tokens: 40, latency_ms: 1000 }
      }
    end
  end

  factory :evaluation_configuration, class: 'RAAF::Eval::Models::EvaluationConfiguration' do
    association :evaluation_run
    name { "Model Change Test" }
    configuration_type { "model_change" }
    changes { { model: "claude-3-5-sonnet-20241022", provider: "anthropic" } }
    execution_order { 0 }
  end

  factory :evaluation_result, class: 'RAAF::Eval::Models::EvaluationResult' do
    association :evaluation_run
    association :evaluation_configuration
    result_span_id { SecureRandom.uuid }
    status { "completed" }
    token_metrics do
      {
        baseline: { total: 50, input: 10, output: 40 },
        result: { total: 55, input: 10, output: 45 },
        delta: { total: 5, input: 0, output: 5 },
        percentage_change: 10.0
      }
    end
    latency_metrics do
      {
        baseline_ms: 1000,
        result_ms: 1050,
        delta_ms: 50,
        percentage_change: 5.0
      }
    end
    baseline_comparison do
      {
        token_delta: { absolute: 5, percentage: 10.0 },
        latency_delta: { absolute_ms: 50, percentage: 5.0 },
        quality_change: "unchanged",
        regression_detected: false
      }
    end
  end
end
