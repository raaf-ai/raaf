# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Continuous::ResultsController, type: :request do
  let(:policy) { create_policy }
  let(:span_id) { "span_#{SecureRandom.hex(12)}" }
  let(:queue_item) { create_queue_item(evaluation_policy: policy, span_id: span_id) }

  describe "GET /raaf/continuous/results" do
    before do
      3.times do |_i|
        create_result(
          evaluation_queue_item: queue_item,
          evaluation_policy: policy,
          span_id: span_id,
          agent_name: "TestAgent",
          evaluator_name: "test_evaluator",
          evaluator_type: "rule_based",
          status: "good",
          score: 0.9
        )
      end
    end

    it "returns a successful response" do
      get continuous_results_path
      expect(response).to have_http_status(:success)
    end

    it "filters by agent" do
      get continuous_results_path(agent: "TestAgent")
      expect(response).to have_http_status(:success)
    end

    it "filters by status" do
      get continuous_results_path(status: "good")
      expect(response).to have_http_status(:success)
    end

    it "filters by date range" do
      get continuous_results_path(from: 1.week.ago.to_date, to: Date.current)
      expect(response).to have_http_status(:success)
    end

    it "displays summary stats" do
      create_result(
        evaluation_queue_item: queue_item,
        evaluation_policy: policy,
        span_id: "span_#{SecureRandom.hex(12)}",
        agent_name: "TestAgent",
        evaluator_name: "test_evaluator",
        evaluator_type: "rule_based",
        status: "bad",
        score: 0.3
      )

      get continuous_results_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /raaf/continuous/results/:id" do
    let(:result) do
      create_result(
        evaluation_queue_item: queue_item,
        evaluation_policy: policy,
        span_id: span_id,
        agent_name: "TestAgent",
        evaluator_name: "test_evaluator",
        evaluator_type: "rule_based",
        status: "good",
        score: 0.9
      )
    end

    it "returns a successful response" do
      get continuous_result_path(result)
      expect(response).to have_http_status(:success)
    end

    it "loads associated span" do
      trace = create_trace
      create_span(span_id: span_id, trace_id: trace.trace_id, name: "test.span",
                  kind: "agent", status: "ok")

      get continuous_result_path(result)
      expect(response).to have_http_status(:success)
    end

    it "loads other results for same span" do
      create_result(
        evaluation_queue_item: queue_item,
        evaluation_policy: policy,
        span_id: span_id,
        agent_name: "TestAgent",
        evaluator_name: "another_evaluator",
        evaluator_type: "llm_judge",
        status: "good",
        score: 0.85
      )

      get continuous_result_path(result)
      expect(response).to have_http_status(:success)
    end
  end
end
