# frozen_string_literal: true

FactoryBot.define do
  # Dataset factories
  factory :dataset, class: "RAAF::Eval::Models::Dataset" do
    name { "Test Dataset #{SecureRandom.hex(4)}" }
    description { "A test dataset for evaluation" }
    version { 1 }
    status { "active" }
    created_by { "test_user" }
    items_count { 0 }
    schema_definition { { input: { query: :string }, expected_output: { response: :string } } }
    metadata { {} }
  end

  factory :dataset_item, class: "RAAF::Eval::Models::DatasetItem" do
    association :dataset
    input { { messages: [{ role: "user", content: "What is Ruby?" }] } }
    expected_output { { messages: [{ role: "assistant", content: "Ruby is a programming language." }] } }
    metadata { {} }
  end

  # Experiment factories
  factory :experiment, class: "RAAF::Eval::Models::Experiment" do
    name { "Test Experiment #{SecureRandom.hex(4)}" }
    description { "Testing agent configuration" }
    association :dataset
    status { "pending" }
    agent_name { "TestAgent" }
    model { "gpt-4o" }
    provider { "openai" }
    configuration { { temperature: 0.7 } }
    total_items { 0 }
    completed_items { 0 }
    failed_items { 0 }
    metadata { {} }
  end

  factory :experiment_result, class: "RAAF::Eval::Models::ExperimentResult" do
    association :experiment
    association :dataset_item
    status { "completed" }
    output { { content: "Test response" } }
    scores { { relevance: 0.9, accuracy: 0.85 } }
    token_metrics { { total_tokens: 150, input_tokens: 50, output_tokens: 100 } }
    latency_metrics { { duration_ms: 250.5 } }
    metadata { {} }
  end

  # Feedback score factories
  factory :feedback_score, class: "RAAF::Eval::Models::FeedbackScore" do
    name { "relevance" }
    source { "ui" }
    span_id { "span_#{SecureRandom.hex(12)}" }
    value { 0.85 }
    scored_by { "reviewer@example.com" }
    metadata { {} }
  end

  factory :feedback_score_definition, class: "RAAF::Eval::Models::FeedbackScoreDefinition" do
    name { "relevance_#{SecureRandom.hex(4)}" }
    description { "How relevant is the response" }
    score_type { "numerical" }
    min_value { 0.0 }
    max_value { 1.0 }
    metadata { {} }
  end

  # Prompt factories
  factory :prompt, class: "RAAF::Eval::Models::Prompt" do
    name { "test_prompt_#{SecureRandom.hex(4)}" }
    description { "A test prompt" }
    agent_name { "TestAgent" }
    latest_version { 0 }
    metadata { {} }
  end

  factory :prompt_version, class: "RAAF::Eval::Models::PromptVersion" do
    association :prompt
    version_number { 1 }
    content { "You are a helpful assistant that answers questions clearly." }
    model { "gpt-4o" }
    model_parameters { { temperature: 0.7 } }
    commit_message { "Initial version" }
    created_by { "developer" }
    status { "draft" }
    metadata { {} }
  end
end
