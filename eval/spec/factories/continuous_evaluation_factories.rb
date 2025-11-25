# frozen_string_literal: true

FactoryBot.define do
  factory :evaluation_policy, class: "RAAF::Eval::Models::EvaluationPolicy" do
    name { "Test Policy #{SecureRandom.hex(4)}" }
    description { "Test policy for evaluating agent spans" }
    agent_name { "TestAgent" }
    environment { "all" }
    model_pattern { "all" }
    version_pattern { "all" }
    sampling_mode { "percentage" }
    sample_rate { 10 }
    sample_every_n { nil }
    sample_counter { 0 }
    max_daily_evaluations { 100 }
    today_evaluation_count { 0 }
    count_reset_date { Date.current }
    priority { 50 }
    queue_name { "raaf_evaluations" }
    max_concurrent_evaluations { 5 }
    max_retries { 3 }
    retention_days { 90 }
    retention_count { nil }
    evaluators do
      [
        { "type" => "rule_based", "name" => "token_limit", "config" => { "max_tokens" => 4000 } }
      ]
    end
    metadata { {} }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :every_n_sampling do
      sampling_mode { "every_n" }
      sample_every_n { 5 }
      sample_rate { nil }
    end

    trait :all_spans do
      sampling_mode { "all" }
      sample_rate { nil }
      sample_every_n { nil }
    end

    trait :with_llm_judge do
      evaluators do
        [
          { "type" => "llm_judge", "name" => "quality_check", "config" => {
            "model" => "gpt-4o-mini",
            "criteria" => ["accuracy", "completeness"]
          } }
        ]
      end
    end

    trait :with_multiple_evaluators do
      evaluators do
        [
          { "type" => "rule_based", "name" => "token_limit", "config" => { "max_tokens" => 4000 } },
          { "type" => "rule_based", "name" => "latency_check", "config" => { "max_ms" => 5000 } },
          { "type" => "llm_judge", "name" => "quality_check", "config" => {
            "model" => "gpt-4o-mini",
            "criteria" => ["accuracy"]
          } }
        ]
      end
    end

    trait :production do
      environment { "production" }
    end

    trait :high_priority do
      priority { 90 }
    end

    trait :at_daily_limit do
      max_daily_evaluations { 10 }
      today_evaluation_count { 10 }
    end
  end

  factory :evaluation_queue_item, class: "RAAF::Eval::Models::EvaluationQueueItem" do
    span_id { SecureRandom.uuid }
    trace_id { SecureRandom.uuid }
    association :evaluation_policy
    status { "pending" }
    priority { 50 }
    attempts { 0 }
    max_attempts { 3 }
    scheduled_at { Time.current }
    started_at { nil }
    completed_at { nil }
    next_retry_at { nil }
    error_message { nil }
    error_class { nil }
    metadata { {} }

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.minute.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      attempts { 3 }
      error_message { "Evaluation failed after max retries" }
      error_class { "RAAF::Eval::EvaluationError" }
    end

    trait :retrying do
      status { "pending" }
      attempts { 1 }
      next_retry_at { 5.minutes.from_now }
    end

    trait :high_priority do
      priority { 90 }
    end
  end

  factory :continuous_evaluation_result, class: "RAAF::Eval::Models::ContinuousEvaluationResult" do
    span_id { SecureRandom.uuid }
    trace_id { SecureRandom.uuid }
    association :evaluation_policy
    evaluation_queue_item { nil }
    evaluation_type { "automated" }
    evaluator_name { "token_limit" }
    evaluator_type { "rule_based" }
    evaluator_version { "1.0.0" }
    agent_name { "TestAgent" }
    agent_version { "1.0" }
    model { "gpt-4o" }
    provider { "openai" }
    environment { "production" }
    status { "passed" }
    score { 0.85 }
    scores { { "quality" => 0.85 } }
    metrics { { "latency_ms" => 1200, "tokens" => 500 } }
    reasoning { "Token usage within limits" }
    details { {} }
    evaluation_duration_ms { 150 }
    evaluation_started_at { 1.second.ago }
    evaluation_completed_at { Time.current }
    metadata { {} }

    trait :failed do
      status { "failed" }
      score { 0.3 }
      reasoning { "Token usage exceeded limit" }
    end

    trait :warning do
      status { "warning" }
      score { 0.6 }
      reasoning { "Token usage approaching limit" }
    end

    trait :error do
      status { "error" }
      score { nil }
      reasoning { "Evaluation failed with error" }
    end

    trait :llm_judge do
      evaluator_type { "llm_judge" }
      evaluator_name { "quality_check" }
      scores { { "accuracy" => 0.9, "completeness" => 0.8 } }
      reasoning { "Response is accurate and mostly complete" }
    end

    trait :statistical do
      evaluator_type { "statistical" }
      evaluator_name { "consistency" }
      scores { { "consistency" => 0.95 } }
    end
  end

  factory :evaluation_metric, class: "RAAF::Eval::Models::EvaluationMetric" do
    agent_name { "TestAgent" }
    environment { "production" }
    model { "gpt-4o" }
    evaluator_name { "token_limit" }
    period_type { "daily" }
    period_start { Date.current.beginning_of_day }
    total_evaluations { 100 }
    passed_count { 85 }
    failed_count { 10 }
    warning_count { 5 }
    error_count { 0 }
    avg_score { 0.85 }
    min_score { 0.3 }
    max_score { 1.0 }
    stddev_score { 0.15 }
    p50_score { 0.87 }
    p90_score { 0.95 }
    p95_score { 0.98 }
    score_distribution do
      {
        "0.0-0.1" => 0,
        "0.1-0.2" => 0,
        "0.2-0.3" => 2,
        "0.3-0.4" => 3,
        "0.4-0.5" => 5,
        "0.5-0.6" => 5,
        "0.6-0.7" => 10,
        "0.7-0.8" => 15,
        "0.8-0.9" => 35,
        "0.9-1.0" => 25
      }
    end
    avg_evaluation_duration_ms { 250.5 }
    total_evaluation_cost { 1.5 }
    additional_metrics { {} }

    trait :hourly do
      period_type { "hourly" }
      period_start { Time.current.beginning_of_hour }
      total_evaluations { 10 }
      passed_count { 8 }
      failed_count { 1 }
      warning_count { 1 }
    end

    trait :weekly do
      period_type { "weekly" }
      period_start { Date.current.beginning_of_week.beginning_of_day }
      total_evaluations { 700 }
      passed_count { 595 }
      failed_count { 70 }
      warning_count { 35 }
    end

    trait :low_pass_rate do
      passed_count { 30 }
      failed_count { 60 }
      warning_count { 10 }
      avg_score { 0.45 }
    end
  end
end
