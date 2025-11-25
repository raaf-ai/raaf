# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanRecord, type: :model do
  describe "continuous evaluation hook" do
    let(:trace) { create(:trace_record) }
    let(:span_attributes) do
      {
        span_id: "span_#{SecureRandom.hex(12)}",
        trace_id: trace.trace_id,
        name: "test_span",
        kind: "agent",
        status: "ok",
        start_time: Time.current,
        end_time: Time.current + 1.second,
        duration_ms: 1000,
        span_attributes: { agent: { name: "TestAgent" } }
      }
    end

    before do
      # Ensure continuous evaluation module is loaded
      require "raaf/eval/continuous"
    end

    context "when continuous evaluation is enabled" do
      before do
        RAAF::Eval::Continuous.enable!
        RAAF::Eval::Continuous.configuration.hook_enabled = true
      end

      after do
        RAAF::Eval::Continuous.disable!
      end

      it "calls the hook on span creation" do
        expect_any_instance_of(described_class).to receive(:enqueue_continuous_evaluations).and_call_original
        described_class.create!(span_attributes)
      end

      context "with matching policies" do
        let!(:policy) do
          RAAF::Eval::Models::EvaluationPolicy.create!(
            name: "Test Policy",
            description: "Test policy for specs",
            target_agent_names: ["TestAgent"],
            target_environments: [::Rails.env],
            sampling_mode: "all",
            active: true,
            evaluators: [{ name: "test_evaluator", config: {} }]
          )
        end

        it "enqueues evaluation jobs for matching policies" do
          expect(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later).with(
            hash_including(
              policy_id: policy.id
            )
          )

          described_class.create!(span_attributes)
        end

        it "passes the correct span_id to the job" do
          span = described_class.create!(span_attributes)

          expect(RAAF::Eval::Continuous::EvaluationJob).to have_received(:perform_later).with(
            hash_including(
              span_id: span.span_id,
              policy_id: policy.id
            )
          )
        end
      end

      context "with no matching policies" do
        before do
          # Create a policy that doesn't match
          RAAF::Eval::Models::EvaluationPolicy.create!(
            name: "Other Policy",
            description: "Policy for different agent",
            target_agent_names: ["OtherAgent"],
            target_environments: [::Rails.env],
            sampling_mode: "all",
            active: true,
            evaluators: [{ name: "test_evaluator", config: {} }]
          )
        end

        it "does not enqueue any jobs" do
          expect(RAAF::Eval::Continuous::EvaluationJob).not_to receive(:perform_later)
          described_class.create!(span_attributes)
        end
      end

      context "when PolicyMatcher raises an error" do
        before do
          allow_any_instance_of(RAAF::Eval::Continuous::PolicyMatcher)
            .to receive(:policies_to_evaluate).and_raise(StandardError, "Test error")
        end

        it "logs the error but does not raise" do
          expect(::Rails.logger).to receive(:warn).with(
            /Failed to enqueue evaluations: Test error/
          )

          expect { described_class.create!(span_attributes) }.not_to raise_error
        end

        it "still creates the span successfully" do
          span = nil
          expect { span = described_class.create!(span_attributes) }.not_to raise_error
          expect(span).to be_persisted
          expect(span.span_id).to be_present
        end
      end

      context "when job enqueueing fails" do
        let!(:policy) do
          RAAF::Eval::Models::EvaluationPolicy.create!(
            name: "Test Policy",
            description: "Test policy",
            target_agent_names: ["TestAgent"],
            target_environments: [::Rails.env],
            sampling_mode: "all",
            active: true,
            evaluators: [{ name: "test_evaluator", config: {} }]
          )
        end

        before do
          allow(RAAF::Eval::Continuous::EvaluationJob)
            .to receive(:perform_later).and_raise(StandardError, "Queue error")
        end

        it "logs the error but does not raise" do
          expect(::Rails.logger).to receive(:warn).with(
            /Failed to enqueue evaluations: Queue error/
          )

          expect { described_class.create!(span_attributes) }.not_to raise_error
        end

        it "still creates the span successfully" do
          span = nil
          expect { span = described_class.create!(span_attributes) }.not_to raise_error
          expect(span).to be_persisted
        end
      end
    end

    context "when continuous evaluation is disabled via enabled?" do
      before do
        RAAF::Eval::Continuous.disable!
      end

      it "does not call PolicyMatcher" do
        expect(RAAF::Eval::Continuous::PolicyMatcher).not_to receive(:new)
        described_class.create!(span_attributes)
      end

      it "does not enqueue any jobs" do
        expect(RAAF::Eval::Continuous::EvaluationJob).not_to receive(:perform_later)
        described_class.create!(span_attributes)
      end

      it "still creates the span successfully" do
        span = described_class.create!(span_attributes)
        expect(span).to be_persisted
        expect(span.span_id).to be_present
      end
    end

    context "when continuous evaluation hook is disabled via hook_enabled" do
      before do
        RAAF::Eval::Continuous.enable!
        RAAF::Eval::Continuous.configuration.hook_enabled = false
      end

      after do
        RAAF::Eval::Continuous.disable!
      end

      it "does not call PolicyMatcher" do
        expect(RAAF::Eval::Continuous::PolicyMatcher).not_to receive(:new)
        described_class.create!(span_attributes)
      end

      it "does not enqueue any jobs" do
        expect(RAAF::Eval::Continuous::EvaluationJob).not_to receive(:perform_later)
        described_class.create!(span_attributes)
      end

      it "still creates the span successfully" do
        span = described_class.create!(span_attributes)
        expect(span).to be_persisted
        expect(span.span_id).to be_present
      end
    end

    context "when RAAF::Eval::Continuous is not defined" do
      before do
        # Simulate the module not being loaded
        hide_const("RAAF::Eval::Continuous")
      end

      it "does not raise an error" do
        expect { described_class.create!(span_attributes) }.not_to raise_error
      end

      it "still creates the span successfully" do
        span = described_class.create!(span_attributes)
        expect(span).to be_persisted
        expect(span.span_id).to be_present
      end
    end

    describe "hook overhead" do
      before do
        RAAF::Eval::Continuous.enable!
        RAAF::Eval::Continuous.configuration.hook_enabled = true
      end

      after do
        RAAF::Eval::Continuous.disable!
      end

      it "completes span creation in under 5ms additional overhead" do
        # Measure baseline span creation time (no policies)
        baseline_times = []
        5.times do
          start_time = Time.now
          described_class.create!(span_attributes.merge(
            span_id: "span_#{SecureRandom.hex(12)}"
          ))
          baseline_times << (Time.now - start_time)
        end
        baseline_avg = baseline_times.sum / baseline_times.size

        # Create a policy to trigger the hook
        RAAF::Eval::Models::EvaluationPolicy.create!(
          name: "Overhead Test Policy",
          description: "Policy for overhead testing",
          target_agent_names: ["TestAgent"],
          target_environments: [::Rails.env],
          sampling_mode: "all",
          active: true,
          evaluators: [{ name: "test_evaluator", config: {} }]
        )

        # Stub job enqueueing to just measure hook overhead
        allow(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later)

        # Measure with hook enabled
        hook_times = []
        5.times do
          start_time = Time.now
          described_class.create!(span_attributes.merge(
            span_id: "span_#{SecureRandom.hex(12)}"
          ))
          hook_times << (Time.now - start_time)
        end
        hook_avg = hook_times.sum / hook_times.size

        # Calculate overhead
        overhead_ms = (hook_avg - baseline_avg) * 1000

        # Verify overhead is under 5ms
        expect(overhead_ms).to be < 5.0
      end
    end
  end
end
