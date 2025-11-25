# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RAAF::Rails::Continuous::AnalyticsController, type: :request do
  let(:policy) { EvaluationPolicy.create!(name: 'Test Policy', agent_name: 'TestAgent', evaluators: []) }
  let(:queue_item) { EvaluationQueue.create!(evaluation_policy: policy, span_id: 'span-1') }

  before do
    # Create sample evaluation results
    5.times do |i|
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        span_id: "span-#{i}",
        agent_name: 'TestAgent',
        model: 'gpt-4o',
        evaluator_name: 'test_evaluator',
        evaluator_type: 'rule_based',
        status: i < 4 ? 'passed' : 'failed',
        score: i < 4 ? 0.9 : 0.3,
        metrics: { latency_ms: 1000, cost: 0.01 }
      )
    end
  end

  describe "GET /raaf/rails/continuous/analytics" do
    it "returns a successful response" do
      get raaf_rails_continuous_analytics_path
      expect(response).to have_http_status(:success)
    end

    it "calculates overview stats" do
      get raaf_rails_continuous_analytics_path(agent: 'TestAgent')
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /raaf/rails/continuous/analytics/pass_rate_data" do
    before do
      # Create metrics for time-series data
      3.days.ago.to_date.upto(Date.current) do |date|
        EvaluationMetric.create!(
          agent_name: 'TestAgent',
          period_type: 'daily',
          period_start: date.beginning_of_day,
          period_end: date.end_of_day,
          total_evaluations: 10,
          passed_count: 8,
          failed_count: 2,
          warning_count: 0
        )
      end
    end

    it "returns JSON data for time-series chart" do
      get pass_rate_data_raaf_rails_continuous_analytics_path(agent: 'TestAgent'), as: :json
      expect(response).to have_http_status(:success)

      data = JSON.parse(response.body)
      expect(data).to be_an(Array)
      expect(data.first).to have_key('date')
      expect(data.first).to have_key('pass_rate')
      expect(data.first).to have_key('total')
    end

    it "filters by date range" do
      get pass_rate_data_raaf_rails_continuous_analytics_path(
        agent: 'TestAgent',
        from: 2.days.ago.to_date,
        to: Date.current
      ), as: :json

      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /raaf/rails/continuous/analytics/score_distribution_data" do
    before do
      # Create metric with score distribution
      EvaluationMetric.create!(
        agent_name: 'TestAgent',
        period_type: 'daily',
        period_start: Date.current.beginning_of_day,
        period_end: Date.current.end_of_day,
        total_evaluations: 100,
        passed_count: 80,
        failed_count: 20,
        score_distribution: {
          '0.0-0.1' => 5,
          '0.1-0.2' => 5,
          '0.2-0.3' => 10,
          '0.7-0.8' => 20,
          '0.8-0.9' => 30,
          '0.9-1.0' => 30
        }
      )
    end

    it "returns JSON data for histogram" do
      get score_distribution_data_raaf_rails_continuous_analytics_path(agent: 'TestAgent'), as: :json
      expect(response).to have_http_status(:success)

      data = JSON.parse(response.body)
      expect(data).to be_an(Array)
      expect(data.length).to eq(10)
      expect(data.first).to have_key('range')
      expect(data.first).to have_key('count')
    end
  end

  describe "GET /raaf/rails/continuous/analytics/model_comparison_data" do
    before do
      # Add some results with different models
      2.times do |i|
        EvaluationResult.create!(
          evaluation_queue: queue_item,
          evaluation_policy: policy,
          span_id: "span-claude-#{i}",
          agent_name: 'TestAgent',
          model: 'claude-3-5-sonnet-20241022',
          evaluator_name: 'test_evaluator',
          evaluator_type: 'rule_based',
          status: 'passed',
          score: 0.95,
          metrics: { latency_ms: 1500, cost: 0.02 }
        )
      end
    end

    it "returns JSON data for model comparison" do
      get model_comparison_data_raaf_rails_continuous_analytics_path(agent: 'TestAgent'), as: :json
      expect(response).to have_http_status(:success)

      data = JSON.parse(response.body)
      expect(data).to be_an(Array)
      expect(data.first).to have_key('model')
      expect(data.first).to have_key('total_evaluations')
      expect(data.first).to have_key('pass_rate')
      expect(data.first).to have_key('avg_score')
      expect(data.first).to have_key('avg_latency_ms')
      expect(data.first).to have_key('total_cost')
    end
  end

  describe "GET /raaf/rails/continuous/analytics/failure_analysis_data" do
    before do
      # Create failed results with different evaluators
      3.times do |i|
        EvaluationResult.create!(
          evaluation_queue: queue_item,
          evaluation_policy: policy,
          span_id: "failed-span-#{i}",
          agent_name: 'TestAgent',
          evaluator_name: "evaluator_#{i % 2}",
          evaluator_type: 'rule_based',
          status: 'failed',
          score: 0.2
        )
      end
    end

    it "returns JSON data for failure breakdown" do
      get failure_analysis_data_raaf_rails_continuous_analytics_path(agent: 'TestAgent'), as: :json
      expect(response).to have_http_status(:success)

      data = JSON.parse(response.body)
      expect(data).to be_an(Array)
      expect(data.first).to have_key('evaluator')
      expect(data.first).to have_key('count')
      expect(data.first).to have_key('percentage')
    end

    it "sorts by count descending" do
      get failure_analysis_data_raaf_rails_continuous_analytics_path(agent: 'TestAgent'), as: :json
      data = JSON.parse(response.body)

      counts = data.map { |d| d['count'] }
      expect(counts).to eq(counts.sort.reverse)
    end
  end
end
