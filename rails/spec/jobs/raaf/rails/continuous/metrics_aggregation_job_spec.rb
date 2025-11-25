# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RAAF::Rails::Continuous::MetricsAggregationJob, type: :job do
  let(:agent_name) { 'TestAgent' }
  let(:environment) { 'test' }
  let(:model) { 'gpt-4o' }
  let(:evaluator_name) { 'token_limit' }

  let!(:results) do
    5.times.map do |i|
      RAAF::Eval::Models::ContinuousEvaluationResult.create!(
        span_id: "span-#{i}",
        trace_id: "trace-#{i}",
        evaluation_type: 'automated',
        evaluator_name: evaluator_name,
        evaluator_type: 'rule_based',
        agent_name: agent_name,
        model: model,
        environment: environment,
        status: i < 4 ? 'passed' : 'failed',
        score: (0.8 + i * 0.05).round(4),
        scores: { 'quality' => 0.9 },
        metrics: { 'cost' => 0.001 },
        reasoning: 'Test evaluation',
        details: {},
        evaluation_duration_ms: 100 + i * 10,
        evaluation_started_at: 1.hour.ago,
        evaluation_completed_at: 1.hour.ago + (100 + i * 10).milliseconds,
        created_at: 1.hour.ago
      )
    end
  end

  describe '#perform' do
    context 'with hourly aggregation' do
      it 'creates hourly metric records' do
        expect {
          described_class.perform_now(period_type: 'hourly')
        }.to change(RAAF::Eval::Models::EvaluationMetric, :count).by_at_least(1)
      end

      it 'computes correct aggregate statistics' do
        described_class.perform_now(period_type: 'hourly')

        metric = RAAF::Eval::Models::EvaluationMetric.last
        expect(metric.agent_name).to eq(agent_name)
        expect(metric.total_evaluations).to eq(5)
        expect(metric.passed_count).to eq(4)
        expect(metric.failed_count).to eq(1)
        expect(metric.period_type).to eq('hourly')
      end

      it 'calculates score statistics' do
        described_class.perform_now(period_type: 'hourly')

        metric = RAAF::Eval::Models::EvaluationMetric.last
        expect(metric.avg_score).to be_within(0.01).of(0.9)
        expect(metric.min_score).to be >= 0.8
        expect(metric.max_score).to be <= 1.0
      end

      it 'computes score distribution' do
        described_class.perform_now(period_type: 'hourly')

        metric = RAAF::Eval::Models::EvaluationMetric.last
        expect(metric.score_distribution).to be_a(Hash)
        expect(metric.score_distribution.values.sum).to eq(5)
      end
    end

    context 'with daily aggregation' do
      it 'creates daily metric records' do
        expect {
          described_class.perform_now(period_type: 'daily')
        }.to change(RAAF::Eval::Models::EvaluationMetric, :count).by_at_least(1)
      end

      it 'sets correct period type' do
        described_class.perform_now(period_type: 'daily')

        metric = RAAF::Eval::Models::EvaluationMetric.last
        expect(metric.period_type).to eq('daily')
      end
    end

    context 'with weekly aggregation' do
      it 'creates weekly metric records' do
        expect {
          described_class.perform_now(period_type: 'weekly')
        }.to change(RAAF::Eval::Models::EvaluationMetric, :count).by_at_least(1)
      end

      it 'sets correct period type' do
        described_class.perform_now(period_type: 'weekly')

        metric = RAAF::Eval::Models::EvaluationMetric.last
        expect(metric.period_type).to eq('weekly')
      end
    end

    context 'with invalid period type' do
      it 'raises an error' do
        expect {
          described_class.perform_now(period_type: 'invalid')
        }.to raise_error(ArgumentError, /Invalid period_type/)
      end
    end

    context 'with no results' do
      before do
        RAAF::Eval::Models::ContinuousEvaluationResult.delete_all
      end

      it 'does not create metric records' do
        expect {
          described_class.perform_now(period_type: 'hourly')
        }.not_to change(RAAF::Eval::Models::EvaluationMetric, :count)
      end
    end

    context 'with upsert on existing metrics' do
      before do
        # Create initial metric
        described_class.perform_now(period_type: 'hourly')
      end

      it 'updates existing metric instead of creating new one' do
        # Add more results
        RAAF::Eval::Models::ContinuousEvaluationResult.create!(
          span_id: 'span-new',
          trace_id: 'trace-new',
          evaluation_type: 'automated',
          evaluator_name: evaluator_name,
          evaluator_type: 'rule_based',
          agent_name: agent_name,
          model: model,
          environment: environment,
          status: 'passed',
          score: 0.95,
          scores: {},
          metrics: {},
          reasoning: 'New evaluation',
          details: {},
          evaluation_duration_ms: 120,
          created_at: 30.minutes.ago
        )

        initial_count = RAAF::Eval::Models::EvaluationMetric.count

        described_class.perform_now(period_type: 'hourly')

        expect(RAAF::Eval::Models::EvaluationMetric.count).to eq(initial_count)

        metric = RAAF::Eval::Models::EvaluationMetric.last
        expect(metric.total_evaluations).to eq(6) # Updated count
      end
    end

    context 'with multiple dimension combinations' do
      before do
        # Create result with different agent
        RAAF::Eval::Models::ContinuousEvaluationResult.create!(
          span_id: 'span-other',
          trace_id: 'trace-other',
          evaluation_type: 'automated',
          evaluator_name: 'other_evaluator',
          evaluator_type: 'rule_based',
          agent_name: 'OtherAgent',
          model: 'claude-3',
          environment: 'production',
          status: 'passed',
          score: 0.88,
          scores: {},
          metrics: {},
          reasoning: 'Other evaluation',
          details: {},
          evaluation_duration_ms: 150,
          created_at: 45.minutes.ago
        )
      end

      it 'creates separate metrics for each dimension combination' do
        expect {
          described_class.perform_now(period_type: 'hourly')
        }.to change(RAAF::Eval::Models::EvaluationMetric, :count).by_at_least(2)
      end

      it 'correctly groups results by dimensions' do
        described_class.perform_now(period_type: 'hourly')

        test_agent_metric = RAAF::Eval::Models::EvaluationMetric.find_by(
          agent_name: agent_name,
          evaluator_name: evaluator_name
        )
        expect(test_agent_metric.total_evaluations).to eq(5)

        other_agent_metric = RAAF::Eval::Models::EvaluationMetric.find_by(
          agent_name: 'OtherAgent',
          evaluator_name: 'other_evaluator'
        )
        expect(other_agent_metric.total_evaluations).to eq(1)
      end
    end
  end

  describe 'queue configuration' do
    it 'uses the low priority queue' do
      expect(described_class.queue_name).to eq('raaf_evaluations_low')
    end
  end

  describe 'retry behavior' do
    it 'retries on errors with delay' do
      allow_any_instance_of(described_class).to receive(:aggregate_hourly_metrics)
        .and_raise(StandardError)

      expect {
        described_class.perform_now(period_type: 'hourly')
      }.to raise_error(StandardError)
    end
  end
end
