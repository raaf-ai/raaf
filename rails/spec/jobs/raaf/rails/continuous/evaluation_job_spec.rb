# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RAAF::Rails::Continuous::EvaluationJob, type: :job do
  let(:span) do
    RAAF::Rails::Tracing::SpanRecord.create!(
      span_id: 'span-123',
      trace_id: 'trace-123',
      parent_id: nil,
      type: 'agent',
      data: {
        'agent' => { 'name' => 'TestAgent' },
        'request' => { 'model' => 'gpt-4o', 'messages' => [{ 'role' => 'user', 'content' => 'test' }] },
        'response' => { 'content' => 'response', 'usage' => { 'total_tokens' => 100 } }
      },
      metadata: { 'agent_name' => 'TestAgent', 'model' => 'gpt-4o', 'provider' => 'openai' },
      started_at: Time.current,
      ended_at: Time.current + 1.second
    )
  end

  let(:policy) do
    RAAF::Eval::Models::EvaluationPolicy.create!(
      name: 'test-policy',
      agent_name: 'TestAgent',
      environment: 'test',
      sampling_mode: 'all',
      priority: 50,
      evaluators: [
        { 'type' => 'rule_based', 'name' => 'token_limit', 'config' => { 'max_tokens' => 1000 } }
      ]
    )
  end

  describe '#perform' do
    context 'with valid span and policy' do
      it 'creates a queue item' do
        expect {
          described_class.perform_now(span_id: span.span_id, policy_id: policy.id)
        }.to change(RAAF::Eval::Models::EvaluationQueueItem, :count).by(1)
      end

      it 'executes evaluators and stores results' do
        # Mock evaluator
        evaluator = instance_double(RAAF::Eval::DSL::Evaluator)
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(evaluator)

        # Mock evaluation result
        result = double(
          passed?: true,
          failed?: false,
          warning?: false,
          score: 0.95,
          field_scores: { 'quality' => 0.95 },
          reasoning: 'Test passed',
          to_h: { 'status' => 'passed' }
        )
        allow(evaluator).to receive(:evaluate).and_return(result)

        expect {
          described_class.perform_now(span_id: span.span_id, policy_id: policy.id)
        }.to change(RAAF::Eval::Models::ContinuousEvaluationResult, :count).by(1)
      end

      it 'marks queue item as completed' do
        evaluator = instance_double(RAAF::Eval::DSL::Evaluator)
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(evaluator)

        result = double(
          passed?: true,
          failed?: false,
          warning?: false,
          score: 0.95,
          field_scores: {},
          reasoning: 'Test passed',
          to_h: {}
        )
        allow(evaluator).to receive(:evaluate).and_return(result)

        described_class.perform_now(span_id: span.span_id, policy_id: policy.id)

        queue_item = RAAF::Eval::Models::EvaluationQueueItem.last
        expect(queue_item.status).to eq('completed')
      end

      it 'increments policy evaluation count' do
        evaluator = instance_double(RAAF::Eval::DSL::Evaluator)
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(evaluator)

        result = double(
          passed?: true,
          failed?: false,
          warning?: false,
          score: 0.95,
          field_scores: {},
          reasoning: 'Test passed',
          to_h: {}
        )
        allow(evaluator).to receive(:evaluate).and_return(result)

        expect {
          described_class.perform_now(span_id: span.span_id, policy_id: policy.id)
        }.to change { policy.reload.today_evaluation_count }.by(1)
      end
    end

    context 'with non-existent span' do
      it 'raises SpanNotFoundError' do
        expect {
          described_class.perform_now(span_id: 'non-existent', policy_id: policy.id)
        }.to raise_error(RAAF::Eval::SpanNotFoundError)
      end

      it 'does not create a queue item' do
        expect {
          begin
            described_class.perform_now(span_id: 'non-existent', policy_id: policy.id)
          rescue RAAF::Eval::SpanNotFoundError
            # Suppress error for count check
          end
        }.not_to change(RAAF::Eval::Models::EvaluationQueueItem, :count)
      end
    end

    context 'with evaluator failure' do
      it 'marks queue item as failed' do
        evaluator = instance_double(RAAF::Eval::DSL::Evaluator)
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(evaluator)
        allow(evaluator).to receive(:evaluate).and_raise(StandardError, 'Evaluator failed')

        expect {
          described_class.perform_now(span_id: span.span_id, policy_id: policy.id)
        }.to raise_error(StandardError)

        queue_item = RAAF::Eval::Models::EvaluationQueueItem.last
        expect(queue_item.status).to eq('pending') # Goes back to pending for retry
        expect(queue_item.error_message).to eq('Evaluator failed')
      end

      it 'does not increment policy counter on failure' do
        evaluator = instance_double(RAAF::Eval::DSL::Evaluator)
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(evaluator)
        allow(evaluator).to receive(:evaluate).and_raise(StandardError, 'Evaluator failed')

        expect {
          begin
            described_class.perform_now(span_id: span.span_id, policy_id: policy.id)
          rescue StandardError
            # Suppress error
          end
        }.not_to change { policy.reload.today_evaluation_count }
      end
    end

    context 'with multiple evaluators' do
      let(:multi_evaluator_policy) do
        RAAF::Eval::Models::EvaluationPolicy.create!(
          name: 'multi-evaluator-policy',
          agent_name: 'TestAgent',
          environment: 'test',
          sampling_mode: 'all',
          evaluators: [
            { 'type' => 'rule_based', 'name' => 'token_limit', 'config' => { 'max_tokens' => 1000 } },
            { 'type' => 'rule_based', 'name' => 'latency_check', 'config' => { 'max_ms' => 5000 } }
          ]
        )
      end

      it 'executes all evaluators' do
        evaluator1 = instance_double(RAAF::Eval::DSL::Evaluator)
        evaluator2 = instance_double(RAAF::Eval::DSL::Evaluator)

        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build)
          .and_return(evaluator1, evaluator2)

        result = double(
          passed?: true,
          failed?: false,
          warning?: false,
          score: 0.95,
          field_scores: {},
          reasoning: 'Test passed',
          to_h: {}
        )

        expect(evaluator1).to receive(:evaluate).and_return(result)
        expect(evaluator2).to receive(:evaluate).and_return(result)

        expect {
          described_class.perform_now(span_id: span.span_id, policy_id: multi_evaluator_policy.id)
        }.to change(RAAF::Eval::Models::ContinuousEvaluationResult, :count).by(2)
      end
    end
  end

  describe 'retry behavior' do
    it 'retries on transient errors' do
      expect(described_class).to have_been_enqueued.with(
        span_id: span.span_id,
        policy_id: policy.id
      ).on_queue('raaf_evaluations')
    end

    it 'discards on permanent errors' do
      allow(RAAF::Rails::Tracing::SpanRecord).to receive(:find_by).and_return(nil)

      expect {
        described_class.perform_now(span_id: 'missing', policy_id: policy.id)
      }.to raise_error(RAAF::Eval::SpanNotFoundError)
    end
  end
end
