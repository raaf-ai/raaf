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
