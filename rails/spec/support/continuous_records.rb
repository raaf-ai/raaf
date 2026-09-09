# frozen_string_literal: true

# Builds the continuous-evaluation rows the console reads.
#
# Each model validates more than a spec usually cares about -- a queue item
# needs a trace as well as a span, a result needs a quality label from a fixed
# set, a policy's sampling mode has to be one the matcher understands (the
# column's own default, "percentage", is not) -- so the parts a spec is not
# making a point about are filled in here.
module ContinuousRecords
  def create_policy(**attributes)
    RAAF::Eval::Models::EvaluationPolicy.create!(
      { name: "Test Policy",
        agent_name: "TestAgent",
        environment: "all",
        sampling_mode: "all",
        evaluators: [] }.merge(attributes)
    )
  end

  def create_queue_item(**attributes)
    RAAF::Eval::Models::EvaluationQueueItem.create!(
      { span_id: "span-#{SecureRandom.hex(4)}",
        trace_id: "trace-#{SecureRandom.hex(4)}" }.merge(attributes)
    )
  end

  # Statuses are quality labels: good, average, bad, or error. "error" means the
  # scorer broke; "bad" means it worked and disliked the answer.
  def create_result(**attributes)
    RAAF::Eval::Models::ContinuousEvaluationResult.create!(
      { span_id: "span-#{SecureRandom.hex(4)}",
        trace_id: "trace-#{SecureRandom.hex(4)}",
        evaluation_type: "automated",
        evaluator_name: "token_limit",
        evaluator_type: "rule_based",
        agent_name: "TestAgent",
        environment: "test",
        status: "good",
        score: 0.9 }.merge(attributes)
    )
  end

  # A job in the backend the Queue screen reads, written by hand rather than
  # enqueued: the specs run the :test adapter, which keeps jobs in memory, and
  # the screen reads SolidQueue's tables.
  #
  # The arguments go in the shape ActiveJob serializes them into, since that is
  # what JobQueue unwraps to name the span and policy behind a row.
  def create_queue_job(span_id: "span-#{SecureRandom.hex(4)}", policy_id: nil,
                       queue_name: "raaf_evaluations", finished_at: nil)
    SolidQueue::Job.create!(
      queue_name: queue_name,
      class_name: "RAAF::Rails::Continuous::EvaluationJob",
      arguments: { "arguments" => [{ "span_id" => span_id, "policy_id" => policy_id }] },
      priority: 0,
      finished_at: finished_at
    )
  end

  # A job SolidQueue has given up on. Creating a job readies it for execution,
  # as enqueueing one does, so the ready row is cleared: a failed job is not
  # also waiting for a worker.
  def create_failed_job(error: { "exception_class" => "RuntimeError", "message" => "boom" }, **attributes)
    job = create_queue_job(**attributes)
    job.ready_execution&.destroy
    SolidQueue::FailedExecution.create!(job: job, error: error)
    job.reload
  end

  def create_metric(**attributes)
    RAAF::Eval::Models::EvaluationMetric.create!(
      { agent_name: "TestAgent",
        environment: "test",
        period_type: "daily",
        period_start: 1.day.ago.beginning_of_day }.merge(attributes)
    )
  end
end

RSpec.configure do |config|
  config.include ContinuousRecords
end
