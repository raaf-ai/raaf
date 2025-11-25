# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RAAF::Rails::Continuous::ResultsController, type: :request do
  let(:policy) { EvaluationPolicy.create!(name: 'Test Policy', agent_name: 'TestAgent', evaluators: []) }
  let(:queue_item) { EvaluationQueue.create!(evaluation_policy: policy, span_id: 'span-1') }

  describe "GET /raaf/rails/continuous/results" do
    before do
      3.times do |i|
        EvaluationResult.create!(
          evaluation_queue: queue_item,
          evaluation_policy: policy,
          span_id: 'span-1',
          agent_name: 'TestAgent',
          evaluator_name: 'test_evaluator',
          evaluator_type: 'rule_based',
          status: 'passed',
          score: 0.9
        )
      end
    end

    it "returns a successful response" do
      get raaf_rails_continuous_results_path
      expect(response).to have_http_status(:success)
    end

    it "filters by agent" do
      get raaf_rails_continuous_results_path(agent: 'TestAgent')
      expect(response).to have_http_status(:success)
    end

    it "filters by status" do
      get raaf_rails_continuous_results_path(status: 'passed')
      expect(response).to have_http_status(:success)
    end

    it "filters by date range" do
      get raaf_rails_continuous_results_path(from: 1.week.ago.to_date, to: Date.current)
      expect(response).to have_http_status(:success)
    end

    it "displays summary stats" do
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        span_id: 'span-2',
        agent_name: 'TestAgent',
        evaluator_name: 'test_evaluator',
        evaluator_type: 'rule_based',
        status: 'failed',
        score: 0.3
      )

      get raaf_rails_continuous_results_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /raaf/rails/continuous/results/:id" do
    let(:result) do
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        span_id: 'span-1',
        agent_name: 'TestAgent',
        evaluator_name: 'test_evaluator',
        evaluator_type: 'rule_based',
        status: 'passed',
        score: 0.9
      )
    end

    it "returns a successful response" do
      get raaf_rails_continuous_result_path(result)
      expect(response).to have_http_status(:success)
    end

    it "loads associated span" do
      span = RAAF::Rails::Tracing::SpanRecord.create!(
        span_id: 'span-1',
        trace_id: 'trace-1',
        name: 'test.span',
        kind: 'agent',
        status: 'ok'
      )

      get raaf_rails_continuous_result_path(result)
      expect(response).to have_http_status(:success)
    end

    it "loads other results for same span" do
      other_result = EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        span_id: 'span-1',
        agent_name: 'TestAgent',
        evaluator_name: 'another_evaluator',
        evaluator_type: 'llm_judge',
        status: 'passed',
        score: 0.85
      )

      get raaf_rails_continuous_result_path(result)
      expect(response).to have_http_status(:success)
    end
  end
end
