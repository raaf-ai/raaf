# frozen_string_literal: true

FactoryBot.define do
  factory :session, class: "RAAF::Eval::UI::Session" do
    sequence(:name) { |n| "Evaluation Session #{n}" }
    description { "A test evaluation session" }
    session_type { "draft" }
    status { "pending" }
    metadata { {} }

    trait :saved do
      session_type { "saved" }
    end

    trait :archived do
      session_type { "archived" }
    end

    trait :running do
      status { "running" }
    end

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      error_message { "Test error" }
      completed_at { Time.current }
    end
  end

  factory :session_configuration, class: "RAAF::Eval::UI::SessionConfiguration" do
    association :session
    sequence(:name) { |n| "Configuration #{n}" }
    configuration do
      {
        model: "gpt-4o",
        provider: "openai",
        temperature: 0.7,
        max_tokens: 1000
      }
    end
    display_order { 0 }
  end

  factory :session_result, class: "RAAF::Eval::UI::SessionResult" do
    association :session
    association :configuration, factory: :session_configuration
    status { "pending" }
    result_data { {} }
    metrics { {} }

    trait :completed do
      status { "completed" }
      result_data do
        {
          output: "Test output",
          tokens: 150
        }
      end
      metrics do
        {
          latency_ms: 1200,
          cost: 0.003
        }
      end
    end

    trait :failed do
      status { "failed" }
    end
  end
end
