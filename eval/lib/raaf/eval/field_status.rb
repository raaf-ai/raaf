# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # The verdict a graded field is filed under, decided in one place.
    #
    # ContinuousEvaluationResult#status is what every count, scope and
    # dashboard reads: `good_quality`, `unacceptable`, the pass rate, the
    # quality alerts. It is written by the job that stores a result and, for
    # rows written before a fix, by whatever re-stamps them. Both have to reach
    # the same answer from the same field result, so the rule lives here rather
    # than inside either of them.
    #
    #   RAAF::Eval::FieldStatus.for(label: "good", score: 0.75)  # => "good"
    #
    module FieldStatus
      # The verdicts the status column holds, and the only labels an evaluator
      # can hand over unchanged. "error" is not among them: it is a finding
      # about the check, never the check's own answer.
      STORABLE_LABELS = %w[good average bad].freeze

      # Where the score bands fall for a check that named no verdict of its own.
      GOOD_FLOOR = 0.8
      AVERAGE_FLOOR = 0.5

      module_function

      ##
      # @param field_result [Hash] One field's result: :label, :score, :error
      # @return [String] "good", "average", "bad", or "error"
      def for(field_result)
        result = field_result || {}

        # A check whose evaluator raised reached no verdict. The combination
        # arithmetic still handed back a zero, and filing that as "bad" says
        # the agent answered badly when what happened is that the scorer broke —
        # which is the one reading that sends somebody to look at the agent
        # instead of at the check.
        return "error" if fetch(result, :error)

        # An evaluator decides what good means for the thing it measures: a
        # latency check knows the budget it compared against, a judge grades
        # against its rubric, and an evaluator declaring threshold_good: 0.7 has
        # said where its own line sits. Re-deriving a verdict from the bare score
        # substitutes one set of bands for all of them, and the row then says
        # something no evaluator said.
        label = fetch(result, :label).to_s
        return label if STORABLE_LABELS.include?(label)

        from_score(fetch(result, :score))
      end

      ##
      # The fallback for a check that named no verdict, where the score is all
      # there is to read. A check with neither is bad, since nothing about it
      # can be called good.
      # @param score [Float, nil]
      # @return [String] "good", "average", or "bad"
      def from_score(score)
        return "bad" if score.nil?

        return "good" if score >= GOOD_FLOOR
        return "average" if score >= AVERAGE_FLOOR

        "bad"
      end

      # A field result reaches here as symbol keys from an evaluator and as
      # string keys when read back out of the stored JSON.
      def fetch(result, key)
        result[key] || result[key.to_s]
      end
    end
  end
end
