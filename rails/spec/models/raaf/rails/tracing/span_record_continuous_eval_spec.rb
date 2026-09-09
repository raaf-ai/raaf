# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanRecord, type: :model do
  describe "continuous evaluation hook" do
    let(:trace) do
      RAAF::Rails::Tracing::TraceRecord.create!(
        trace_id: "trace_#{SecureRandom.hex(16)}",
        workflow_name: "SpecWorkflow",
        status: "completed",
        started_at: Time.current
      )
    end

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
        span_attributes: { "agent_name" => "TestAgent" }
      }
    end

    def create_policy(name:, agent_name:)
      RAAF::Eval::Models::EvaluationPolicy.create!(
        name: name,
        description: "Policy for specs",
        agent_name: agent_name,
        environment: "all",
        sampling_mode: "all",
        active: true,
        evaluators: [{ "name" => "test_evaluator", "type" => "rule_based", "config" => {} }]
      )
    end

    before do
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
        let!(:policy) { create_policy(name: "Test Policy", agent_name: "TestAgent") }

        before { allow(RAAF::Rails::Continuous::EvaluationJob).to receive(:perform_later) }

        it "enqueues evaluation jobs for matching policies" do
          described_class.create!(span_attributes)

          expect(RAAF::Rails::Continuous::EvaluationJob).to have_received(:perform_later)
            .with(hash_including(policy_id: policy.id))
        end

        it "passes the correct span_id to the job" do
          span = described_class.create!(span_attributes)

          expect(RAAF::Rails::Continuous::EvaluationJob).to have_received(:perform_later)
            .with(hash_including(span_id: span.span_id, policy_id: policy.id))
        end
      end

      context "with no matching policies" do
        before { create_policy(name: "Other Policy", agent_name: "OtherAgent") }

        it "does not enqueue any jobs" do
          expect(RAAF::Rails::Continuous::EvaluationJob).not_to receive(:perform_later)

          described_class.create!(span_attributes)
        end
      end

      context "when PolicyMatcher raises an error" do
        before do
          allow_any_instance_of(RAAF::Eval::Continuous::PolicyMatcher)
            .to receive(:policies_to_evaluate).and_raise(StandardError, "Test error")
        end

        it "logs the error but does not raise" do
          allow(::Rails.logger).to receive(:warn)

          expect { described_class.create!(span_attributes) }.not_to raise_error
          expect(::Rails.logger).to have_received(:warn).with(/Failed to enqueue evaluations: Test error/)
        end

        it "still creates the span successfully" do
          span = nil

          expect { span = described_class.create!(span_attributes) }.not_to raise_error
          expect(span).to be_persisted
          expect(span.span_id).to be_present
        end
      end

      context "when job enqueueing fails" do
        before do
          create_policy(name: "Test Policy", agent_name: "TestAgent")
          allow(RAAF::Rails::Continuous::EvaluationJob)
            .to receive(:perform_later).and_raise(StandardError, "Queue error")
        end

        it "logs the error but does not raise" do
          allow(::Rails.logger).to receive(:warn)

          expect { described_class.create!(span_attributes) }.not_to raise_error
          expect(::Rails.logger).to have_received(:warn).with(/Failed to enqueue evaluations: Queue error/)
        end

        it "still creates the span successfully" do
          span = nil

          expect { span = described_class.create!(span_attributes) }.not_to raise_error
          expect(span).to be_persisted
        end
      end
    end

    context "when continuous evaluation is disabled via enabled?" do
      before { RAAF::Eval::Continuous.disable! }

      it "does not call PolicyMatcher" do
        expect(RAAF::Eval::Continuous::PolicyMatcher).not_to receive(:new)

        described_class.create!(span_attributes)
      end

      it "does not enqueue any jobs" do
        expect(RAAF::Rails::Continuous::EvaluationJob).not_to receive(:perform_later)

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
        RAAF::Eval::Continuous.configuration.hook_enabled = true
      end

      it "does not call PolicyMatcher" do
        expect(RAAF::Eval::Continuous::PolicyMatcher).not_to receive(:new)

        described_class.create!(span_attributes)
      end

      it "does not enqueue any jobs" do
        expect(RAAF::Rails::Continuous::EvaluationJob).not_to receive(:perform_later)

        described_class.create!(span_attributes)
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
        allow(RAAF::Rails::Continuous::EvaluationJob).to receive(:perform_later)
      end

      after { RAAF::Eval::Continuous.disable! }

      WARMUP_WRITES = 5
      MEASURED_WRITES = 25

      # The hook is what makes continuous evaluation safe to leave on in
      # production: it runs on every span written, so what it costs is what
      # tracing costs. Measured against the same writes with no policy to match
      # rather than against a fixed number of milliseconds, so a slow machine
      # moves both figures.
      #
      # Stated as a ratio for the same reason: under load both sides stretch
      # together, and what has to stay true is that the hook is cheap next to
      # the write it hangs off, not that it lands under some millisecond count
      # a busy runner cannot hit. The median is what survives one GC pause --
      # a mean over five writes could be pushed past any budget by a single
      # slow one.
      it "costs a fraction of the write it hangs off" do
        baseline = median_create_time
        create_policy(name: "Overhead Test Policy", agent_name: "TestAgent")
        with_policy = median_create_time

        expect(with_policy).to be < baseline * 2.0
      end

      # Discards the first writes, which pay for connection warm-up and
      # statement preparation on both sides, then takes the median of the rest.
      def median_create_time
        WARMUP_WRITES.times { create_span }

        times = Array.new(MEASURED_WRITES) do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          create_span
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        end.sort

        times[times.size / 2]
      end

      def create_span
        described_class.create!(span_attributes.merge(span_id: "span_#{SecureRandom.hex(12)}"))
      end
    end

    context "when RAAF::Eval::Continuous is not defined" do
      before { hide_const("RAAF::Eval::Continuous") }

      it "does not raise an error" do
        expect { described_class.create!(span_attributes) }.not_to raise_error
      end

      it "still creates the span successfully" do
        span = described_class.create!(span_attributes)

        expect(span).to be_persisted
        expect(span.span_id).to be_present
      end
    end
  end
end
