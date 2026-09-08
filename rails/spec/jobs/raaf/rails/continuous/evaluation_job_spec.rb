# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Continuous::EvaluationJob, type: :job do
  let!(:trace) { create_trace(workflow_name: "TestWorkflow") }

  let(:span) do
    create_span(
      trace_id: trace.trace_id,
      name: "TestAgent",
      kind: "agent",
      status: "ok",
      start_time: Time.current,
      end_time: Time.current + 1.second,
      duration_ms: 1000,
      span_attributes: {
        "agent_name" => "TestAgent",
        "agent.model" => "gpt-4o",
        "input_tokens" => 60,
        "output_tokens" => 40
      }
    )
  end

  # An evaluator only runs for the checks its config names, so a policy without
  # them grades nothing at all.
  def evaluator_config(name, check: "quality")
    { "type" => "rule_based", "name" => name, "checks" => [check],
      "config" => { "max_tokens" => 1000 } }
  end

  def policy_with(*evaluators, name: "test-policy")
    RAAF::Eval::Models::EvaluationPolicy.create!(
      name: name,
      agent_name: "TestAgent",
      environment: "test",
      sampling_mode: "all",
      priority: 50,
      evaluators: evaluators
    )
  end

  # What an evaluator hands back: a verdict per field, and the individual
  # evaluators that produced each one.
  def evaluation_result(score: 0.95, field: "quality", label: nil)
    field_result = { passed: true, score: score, message: "Test passed" }
    field_result[:label] = label if label

    instance_double(
      RAAF::Eval::DSL::EvaluationResult,
      field_results: { field.to_sym => field_result },
      evaluator_results: {}
    )
  end

  def stored_status(score:, label: nil)
    stub_evaluator(result: evaluation_result(score: score, label: label))
    described_class.perform_now(span_id: span.span_id, policy_id: policy.id)

    RAAF::Eval::Models::ContinuousEvaluationResult.last.status
  end

  let(:policy) { policy_with(evaluator_config("token_limit")) }

  def stub_evaluator(result: evaluation_result)
    evaluator = instance_double(RAAF::Eval::DSL::Evaluator)
    allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(evaluator)
    allow(evaluator).to receive(:evaluate).and_return(result)
    evaluator
  end

  describe "#perform" do
    context "with valid span and policy" do
      before { stub_evaluator }

      it "creates a queue item" do
        expect do
          described_class.perform_now(span_id: span.span_id, policy_id: policy.id)
        end.to change(RAAF::Eval::Models::EvaluationQueueItem, :count).by(1)
      end

      it "executes evaluators and stores results" do
        expect do
          described_class.perform_now(span_id: span.span_id, policy_id: policy.id)
        end.to change(RAAF::Eval::Models::ContinuousEvaluationResult, :count).by(1)
      end

      it "marks queue item as completed" do
        described_class.perform_now(span_id: span.span_id, policy_id: policy.id)

        expect(RAAF::Eval::Models::EvaluationQueueItem.last.status).to eq("completed")
      end

      it "increments policy evaluation count" do
        expect do
          described_class.perform_now(span_id: span.span_id, policy_id: policy.id)
        end.to change { policy.reload.today_evaluation_count }.by(1)
      end
    end

    context "with non-existent span" do
      it "raises SpanNotFoundError" do
        expect do
          described_class.new.perform(span_id: "non-existent", policy_id: policy.id)
        end.to raise_error(RAAF::Eval::SpanNotFoundError)
      end

      it "does not create a queue item" do
        expect do
          described_class.perform_now(span_id: "non-existent", policy_id: policy.id)
        end.not_to change(RAAF::Eval::Models::EvaluationQueueItem, :count)
      end
    end

    context "with evaluator failure" do
      before do
        evaluator = instance_double(RAAF::Eval::DSL::Evaluator)
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(evaluator)
        allow(evaluator).to receive(:evaluate).and_raise(StandardError, "Evaluator failed")
      end

      # An evaluator that raises is the scorer breaking, not the run failing, so
      # the queue item goes back to pending for its next attempt rather than
      # taking the whole job down.
      it "marks queue item for retry" do
        described_class.perform_now(span_id: span.span_id, policy_id: policy.id)

        queue_item = RAAF::Eval::Models::EvaluationQueueItem.last
        expect(queue_item.status).to eq("pending")
        expect(queue_item.error_message).to include("Evaluator failed")
      end

      it "records the failure as an errored result" do
        described_class.perform_now(span_id: span.span_id, policy_id: policy.id)

        expect(RAAF::Eval::Models::ContinuousEvaluationResult.last).to have_attributes(
          status: "error", score: nil
        )
      end

      it "does not increment policy counter on failure" do
        expect do
          described_class.perform_now(span_id: span.span_id, policy_id: policy.id)
        end.not_to(change { policy.reload.today_evaluation_count })
      end
    end

    context "with multiple evaluators" do
      let(:multi_evaluator_policy) do
        policy_with(evaluator_config("token_limit"),
                    evaluator_config("latency_check", check: "latency"),
                    name: "multi-evaluator-policy")
      end

      it "executes all evaluators" do
        evaluator1 = instance_double(RAAF::Eval::DSL::Evaluator)
        evaluator2 = instance_double(RAAF::Eval::DSL::Evaluator)
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build)
          .and_return(evaluator1, evaluator2)

        expect(evaluator1).to receive(:evaluate).and_return(evaluation_result)
        expect(evaluator2).to receive(:evaluate).and_return(evaluation_result(field: "latency"))

        expect do
          described_class.perform_now(span_id: span.span_id, policy_id: multi_evaluator_policy.id)
        end.to change(RAAF::Eval::Models::ContinuousEvaluationResult, :count).by(2)
      end
    end

    # What was asked of a field is declared on the evaluator, and the console
    # used to reconstruct it by looking the class up when somebody opened the
    # result. That answers for the evaluator of the same name today rather than
    # the one that did the scoring, so the row writes it down instead.
    context "with an evaluator that declares what its checks measure" do
      before { stub_evaluator }

      let(:declared) do
        [{ field_name: :quality, evaluator_type: :value_range, check_type: :rule_based,
           display_name: "Quality In Range", description: "Quality sits between 0.0 and 1.0",
           options: { min: 0.0, max: 1.0 } },
         { field_name: :latency, evaluator_type: :threshold, check_type: :rule_based,
           display_name: "Fast Enough", description: "Answered inside 2 seconds",
           options: { max_ms: 2000 } }]
      end

      before do
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery)
          .to receive(:find_custom_evaluator_by_name)
          .and_return(class_double("Evaluator", evaluated_checks: declared))
      end

      it "records the checks declared for the field it graded" do
        described_class.perform_now(span_id: span.span_id, policy_id: policy.id)

        stored = RAAF::Eval::Models::ContinuousEvaluationResult.last.details["declared_checks"]
        expect(stored.size).to eq(1)
        expect(stored.first).to include("display_name" => "Quality In Range",
                                        "description" => "Quality sits between 0.0 and 1.0")
      end

      # A row is about one field. Carrying the other fields' checks would put
      # rules under figures they did not produce.
      it "leaves out the checks belonging to other fields" do
        described_class.perform_now(span_id: span.span_id, policy_id: policy.id)

        stored = RAAF::Eval::Models::ContinuousEvaluationResult.last.details["declared_checks"]
        expect(stored.map { |check| check["field_name"] }).to eq(["quality"])
      end
    end

    # An evaluator declares what good means for its own metric: a latency check
    # names the budget it measured against, a judge grades against its rubric,
    # and StakeholderCoverageEvaluator calls 0.7 good. Re-deriving a verdict
    # from the bare score substitutes one set of bands for all of them, and the
    # row then says something no evaluator said.
    context "with an evaluator that states its own verdict" do
      it "keeps a judge's good at a score the fixed bands call average" do
        expect(stored_status(score: 0.75, label: "good")).to eq("good")
      end

      it "keeps a rule-based breach bad at a score the fixed bands call average" do
        expect(stored_status(score: 0.53, label: "bad")).to eq("bad")
      end

      # The one direction that hides a defect rather than inventing one.
      it "keeps a failing check bad at a score the fixed bands call good" do
        expect(stored_status(score: 0.857, label: "bad")).to eq("bad")
      end

      it "keeps average average" do
        expect(stored_status(score: 0.95, label: "average")).to eq("average")
      end

      # status only holds the four verdicts the model validates, so a label
      # outside them is not a verdict this column can carry.
      it "falls back to the score bands for a label it cannot store" do
        expect(stored_status(score: 0.95, label: "excellent")).to eq("good")
      end

      # A crashed check combines to "bad" because the stand-in it contributes
      # scores zero, but it reached no verdict at all. The error flag says so
      # and outranks the label built around it.
      it "files a crashed check as an error even though it combined to bad" do
        result = evaluation_result(score: 0.0, label: "bad")
        allow(result).to receive(:field_results)
          .and_return(quality: { passed: false, score: 0.0, label: "bad", error: true,
                                 message: "Evaluator failed: boom" })
        stub_evaluator(result: result)

        described_class.perform_now(span_id: span.span_id, policy_id: policy.id)

        expect(RAAF::Eval::Models::ContinuousEvaluationResult.last).to have_attributes(
          status: "error", score: nil
        )
      end
    end

    # Nothing forces an evaluator to label its result, and a score still says
    # something on its own.
    context "with an evaluator that states no verdict" do
      it "derives good from the score" do
        expect(stored_status(score: 0.95)).to eq("good")
      end

      it "derives average from the score" do
        expect(stored_status(score: 0.6)).to eq("average")
      end

      it "derives bad from the score" do
        expect(stored_status(score: 0.2)).to eq("bad")
      end
    end

    context "with an evaluator whose class cannot be found" do
      before do
        stub_evaluator
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery)
          .to receive(:find_custom_evaluator_by_name).and_raise(NameError, "gone")
      end

      # Scoring succeeded. Failing to describe the check afterwards is not a
      # reason to lose the verdict.
      it "still stores the verdict, without the checks" do
        expect do
          described_class.perform_now(span_id: span.span_id, policy_id: policy.id)
        end.to change(RAAF::Eval::Models::ContinuousEvaluationResult, :count).by(1)

        expect(RAAF::Eval::Models::ContinuousEvaluationResult.last.details)
          .not_to have_key("declared_checks")
      end
    end
  end

  describe "retry behavior" do
    it "queues an evaluation on the evaluations queue" do
      described_class.perform_later(span_id: span.span_id, policy_id: policy.id)

      expect(described_class).to have_been_enqueued
        .with(span_id: span.span_id, policy_id: policy.id)
        .on_queue("raaf_evaluations")
    end

    # A span that is not there will never arrive, so the job is dropped rather
    # than retried against a row that cannot appear.
    it "discards on permanent errors" do
      expect do
        described_class.perform_now(span_id: "missing", policy_id: policy.id)
      end.not_to raise_error

      expect(described_class).not_to have_been_enqueued
        .with(span_id: "missing", policy_id: policy.id)
    end
  end
end
