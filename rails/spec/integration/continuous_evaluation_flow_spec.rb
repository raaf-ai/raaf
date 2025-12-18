# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Continuous Evaluation End-to-End Flow", type: :integration do
  # This integration test verifies the complete flow:
  # 1. Span creation triggers evaluation hook
  # 2. Policy matching selects appropriate policies
  # 3. EvaluationJob is enqueued
  # 4. EvaluationJob executes evaluators
  # 5. Results are stored correctly
  # 6. Queue item status is updated

  let(:trace) { create(:trace_record) }
  let(:span_attributes) do
    {
      span_id: "span_#{SecureRandom.hex(12)}",
      trace_id: trace.trace_id,
      name: "test_integration_span",
      kind: "agent",
      status: "ok",
      start_time: Time.current,
      end_time: Time.current + 1.second,
      duration_ms: 1000,
      span_attributes: {
        agent: { name: "IntegrationTestAgent" },
        llm: {
          request: { model: "gpt-4o" },
          usage: { input_tokens: 100, output_tokens: 50, total_tokens: 150 }
        },
        response: {
          content: "Test response content"
        }
      },
      metadata: {
        agent_name: "IntegrationTestAgent",
        model: "gpt-4o",
        provider: "openai"
      }
    }
  end

  before do
    # Ensure continuous evaluation is enabled
    RAAF::Eval::Continuous.enable!
    RAAF::Eval::Continuous.configuration.hook_enabled = true
    RAAF::Eval::Continuous.configuration.backpressure_active = false

    # Clear any existing data
    RAAF::Eval::Models::EvaluationQueueItem.delete_all
    RAAF::Eval::Models::ContinuousEvaluationResult.delete_all
    RAAF::Eval::Models::EvaluationPolicy.delete_all
  end

  after do
    RAAF::Eval::Continuous.disable!
  end

  describe "basic flow without evaluators" do
    it "creates a span without enqueueing jobs when no policies exist" do
      expect {
        RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)
      }.not_to change { RAAF::Eval::Models::EvaluationQueueItem.count }
    end
  end

  describe "flow with matching policy" do
    let!(:policy) do
      RAAF::Eval::Models::EvaluationPolicy.create!(
        name: "Integration Test Policy",
        description: "Policy for integration testing",
        target_agent_names: ["IntegrationTestAgent"],
        target_environments: [::Rails.env],
        sampling_mode: "all",
        sample_rate: 100,
        max_daily_evaluations: 1000,
        priority: 50,
        active: true,
        evaluators: [
          { "name" => "test_evaluator", "type" => "rule_based", "config" => {} }
        ]
      )
    end

    it "enqueues an evaluation job when span matches policy" do
      expect(RAAF::Rails::Continuous::EvaluationJob).to receive(:perform_later).with(
        hash_including(
          policy_id: policy.id
        )
      )

      RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)
    end

    context "when job executes" do
      before do
        # Stub the evaluator discovery to return a mock evaluator
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(mock_evaluator)
      end

      let(:mock_evaluator) do
        double("Evaluator").tap do |evaluator|
          allow(evaluator).to receive(:evaluate).and_return(
            OpenStruct.new(
              score: 0.85,
              passed?: true,
              failed?: false,
              warning?: false,
              reasoning: "Test passed",
              field_scores: { output: 0.85 },
              to_h: { score: 0.85, passed: true }
            )
          )
        end
      end

      it "creates queue item and result on job execution" do
        # Create the span (triggers hook)
        span = RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)

        # Manually execute the job (simulating background processing)
        expect {
          RAAF::Rails::Continuous::EvaluationJob.new.perform(
            span_id: span.span_id,
            policy_id: policy.id
          )
        }.to change { RAAF::Eval::Models::EvaluationQueueItem.count }.by(1)
          .and change { RAAF::Eval::Models::ContinuousEvaluationResult.count }.by(1)
      end

      it "marks queue item as completed on success" do
        span = RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)

        RAAF::Rails::Continuous::EvaluationJob.new.perform(
          span_id: span.span_id,
          policy_id: policy.id
        )

        queue_item = RAAF::Eval::Models::EvaluationQueueItem.last
        expect(queue_item.status).to eq("completed")
        expect(queue_item.completed_at).to be_present
      end

      it "stores evaluation result with correct attributes" do
        span = RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)

        RAAF::Rails::Continuous::EvaluationJob.new.perform(
          span_id: span.span_id,
          policy_id: policy.id
        )

        result = RAAF::Eval::Models::ContinuousEvaluationResult.last
        expect(result.span_id).to eq(span.span_id)
        expect(result.trace_id).to eq(span.trace_id)
        expect(result.evaluation_policy_id).to eq(policy.id)
        expect(result.status).to eq("passed")
        expect(result.score).to eq(0.85)
        expect(result.agent_name).to eq("IntegrationTestAgent")
      end

      it "increments policy evaluation count" do
        span = RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)

        expect {
          RAAF::Rails::Continuous::EvaluationJob.new.perform(
            span_id: span.span_id,
            policy_id: policy.id
          )
        }.to change { policy.reload.evaluation_count }.by(1)
      end
    end

    context "with multiple evaluators" do
      let!(:multi_evaluator_policy) do
        RAAF::Eval::Models::EvaluationPolicy.create!(
          name: "Multi-Evaluator Policy",
          description: "Policy with multiple evaluators",
          target_agent_names: ["IntegrationTestAgent"],
          target_environments: [::Rails.env],
          sampling_mode: "all",
          active: true,
          evaluators: [
            { "name" => "evaluator_1", "type" => "rule_based", "config" => {} },
            { "name" => "evaluator_2", "type" => "rule_based", "config" => {} }
          ]
        )
      end

      let(:mock_evaluator_1) do
        double("Evaluator1").tap do |evaluator|
          allow(evaluator).to receive(:evaluate).and_return(
            OpenStruct.new(
              score: 0.90,
              passed?: true,
              failed?: false,
              warning?: false,
              reasoning: "First evaluator passed",
              field_scores: { output: 0.90 },
              to_h: { score: 0.90, passed: true }
            )
          )
        end
      end

      let(:mock_evaluator_2) do
        double("Evaluator2").tap do |evaluator|
          allow(evaluator).to receive(:evaluate).and_return(
            OpenStruct.new(
              score: 0.75,
              passed?: true,
              failed?: false,
              warning?: false,
              reasoning: "Second evaluator passed",
              field_scores: { output: 0.75 },
              to_h: { score: 0.75, passed: true }
            )
          )
        end
      end

      before do
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build)
          .and_return(mock_evaluator_1, mock_evaluator_2)
      end

      it "creates result for each evaluator" do
        span = RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)

        expect {
          RAAF::Rails::Continuous::EvaluationJob.new.perform(
            span_id: span.span_id,
            policy_id: multi_evaluator_policy.id
          )
        }.to change { RAAF::Eval::Models::ContinuousEvaluationResult.count }.by(2)
      end
    end

    context "with partial failure" do
      let!(:partial_failure_policy) do
        RAAF::Eval::Models::EvaluationPolicy.create!(
          name: "Partial Failure Policy",
          description: "Policy to test partial failure",
          target_agent_names: ["IntegrationTestAgent"],
          target_environments: [::Rails.env],
          sampling_mode: "all",
          active: true,
          evaluators: [
            { "name" => "successful_evaluator", "type" => "rule_based", "config" => {} },
            { "name" => "failing_evaluator", "type" => "rule_based", "config" => {} }
          ]
        )
      end

      let(:successful_evaluator) do
        double("SuccessfulEvaluator").tap do |evaluator|
          allow(evaluator).to receive(:evaluate).and_return(
            OpenStruct.new(
              score: 0.85,
              passed?: true,
              failed?: false,
              warning?: false,
              reasoning: "Success",
              field_scores: {},
              to_h: {}
            )
          )
        end
      end

      let(:failing_evaluator) do
        double("FailingEvaluator").tap do |evaluator|
          allow(evaluator).to receive(:evaluate).and_raise(StandardError, "Evaluator failed!")
        end
      end

      before do
        call_count = 0
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build) do
          call_count += 1
          call_count == 1 ? successful_evaluator : failing_evaluator
        end
      end

      it "marks queue item as partial on mixed success/failure" do
        span = RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)

        RAAF::Rails::Continuous::EvaluationJob.new.perform(
          span_id: span.span_id,
          policy_id: partial_failure_policy.id
        )

        queue_item = RAAF::Eval::Models::EvaluationQueueItem.last
        expect(queue_item.status).to eq("partial")
        expect(queue_item.error_message).to include("failing_evaluator")
      end

      it "stores both success and error results" do
        span = RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)

        RAAF::Rails::Continuous::EvaluationJob.new.perform(
          span_id: span.span_id,
          policy_id: partial_failure_policy.id
        )

        results = RAAF::Eval::Models::ContinuousEvaluationResult.where(span_id: span.span_id)
        expect(results.count).to eq(2)
        expect(results.pluck(:status)).to include("passed", "error")
      end
    end
  end

  describe "backpressure handling" do
    let!(:policy) do
      RAAF::Eval::Models::EvaluationPolicy.create!(
        name: "Backpressure Test Policy",
        description: "Policy for backpressure testing",
        target_agent_names: ["IntegrationTestAgent"],
        target_environments: [::Rails.env],
        sampling_mode: "all",
        active: true,
        evaluators: [{ "name" => "test_evaluator", "type" => "rule_based", "config" => {} }]
      )
    end

    it "skips evaluation when backpressure is active" do
      RAAF::Eval::Continuous.configuration.backpressure_active = true

      expect(RAAF::Rails::Continuous::EvaluationJob).not_to receive(:perform_later)

      RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)
    end

    it "enqueues evaluation when backpressure is inactive" do
      RAAF::Eval::Continuous.configuration.backpressure_active = false

      expect(RAAF::Rails::Continuous::EvaluationJob).to receive(:perform_later)

      RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)
    end
  end

  describe "sampling modes" do
    context "with percentage sampling" do
      let!(:percentage_policy) do
        RAAF::Eval::Models::EvaluationPolicy.create!(
          name: "Percentage Sampling Policy",
          description: "Policy with 50% sampling",
          target_agent_names: ["IntegrationTestAgent"],
          target_environments: [::Rails.env],
          sampling_mode: "percentage",
          sample_rate: 50,
          active: true,
          evaluators: [{ "name" => "test_evaluator", "type" => "rule_based", "config" => {} }]
        )
      end

      it "samples approximately the expected percentage" do
        enqueue_count = 0
        allow(RAAF::Rails::Continuous::EvaluationJob).to receive(:perform_later) { enqueue_count += 1 }

        # Create many spans to test sampling
        100.times do |i|
          RAAF::Rails::Tracing::SpanRecord.create!(
            span_attributes.merge(span_id: "span_#{SecureRandom.hex(12)}")
          )
        end

        # With 50% sampling and 100 spans, expect roughly 50 enqueues (allow variance)
        expect(enqueue_count).to be_between(30, 70)
      end
    end

    context "with daily limit" do
      let!(:limited_policy) do
        RAAF::Eval::Models::EvaluationPolicy.create!(
          name: "Limited Policy",
          description: "Policy with daily limit",
          target_agent_names: ["IntegrationTestAgent"],
          target_environments: [::Rails.env],
          sampling_mode: "all",
          max_daily_evaluations: 2,
          active: true,
          evaluators: [{ "name" => "test_evaluator", "type" => "rule_based", "config" => {} }]
        )
      end

      it "stops enqueueing after daily limit is reached" do
        enqueue_count = 0
        allow(RAAF::Rails::Continuous::EvaluationJob).to receive(:perform_later) { enqueue_count += 1 }

        # Simulate the policy already having evaluations today
        limited_policy.update!(evaluation_count: 0, last_evaluation_at: Time.current)

        # Create spans (should only enqueue up to the limit)
        5.times do |i|
          RAAF::Rails::Tracing::SpanRecord.create!(
            span_attributes.merge(span_id: "span_#{SecureRandom.hex(12)}")
          )
          # Simulate incrementing the policy counter
          limited_policy.increment_evaluation_count! if enqueue_count < 2
        end

        expect(enqueue_count).to eq(2)
      end
    end
  end

  describe "error resilience" do
    let!(:policy) do
      RAAF::Eval::Models::EvaluationPolicy.create!(
        name: "Error Test Policy",
        description: "Policy for error testing",
        target_agent_names: ["IntegrationTestAgent"],
        target_environments: [::Rails.env],
        sampling_mode: "all",
        active: true,
        evaluators: [{ "name" => "test_evaluator", "type" => "rule_based", "config" => {} }]
      )
    end

    it "does not fail span creation when evaluation hook raises" do
      allow(RAAF::Eval::Continuous::PolicyMatcher).to receive(:new)
        .and_raise(StandardError, "Unexpected error")

      span = nil
      expect {
        span = RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)
      }.not_to raise_error

      expect(span).to be_persisted
    end

    it "handles non-existent span gracefully in job" do
      expect {
        RAAF::Rails::Continuous::EvaluationJob.new.perform(
          span_id: "span_nonexistent123456789012",
          policy_id: policy.id
        )
      }.to raise_error(RAAF::Eval::SpanNotFoundError)
    end

    it "handles non-existent policy gracefully in job" do
      span = RAAF::Rails::Tracing::SpanRecord.create!(span_attributes)

      expect {
        RAAF::Rails::Continuous::EvaluationJob.new.perform(
          span_id: span.span_id,
          policy_id: 999999
        )
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
