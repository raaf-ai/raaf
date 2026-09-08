# frozen_string_literal: true

require_relative "../../dsl/evaluator"
require_relative "g_eval"

module RAAF
  module Eval
    module Evaluators
      module LLM
        # A field graded by a model against criteria written in prose.
        #
        # This is the evaluator behind +evaluate_with :llm_judge, criteria: [...]+,
        # and it does no judging of its own: it hands the field and the criteria
        # to {GEval}, which asks a model and reads the answer back.
        #
        # It used to score without asking anything. The score started at 0.7 and
        # moved only if the criteria list contained the exact strings "accuracy",
        # "clarity" or "relevance" — which a list of full sentences never does —
        # so every judged check recorded 0.70 with an empty explanation, on every
        # span, and read on a dashboard as a mediocre agent rather than as a
        # judge that had never run.
        #
        # A score therefore exists here only because a judge produced it. When
        # the judge cannot be reached or answers something unreadable, GEval
        # raises JudgeUnavailableError rather than substituting anything, so the
        # check is recorded as +error+ with no score. "We could not measure
        # this" and "we measured it and it was poor" are different findings and
        # must not arrive looking the same.
        class LlmJudge
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :llm_judge

          DEFAULT_GOOD_THRESHOLD = 0.8
          DEFAULT_AVERAGE_THRESHOLD = 0.6

          # Evaluate a field by asking a model to score it against criteria
          #
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :criteria (required), :good_threshold
          #   (default 0.8), :average_threshold (default 0.6), :model (the judge)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            good_threshold = options[:good_threshold] || DEFAULT_GOOD_THRESHOLD
            average_threshold = options[:average_threshold] || DEFAULT_AVERAGE_THRESHOLD
            criteria = options[:criteria]

            if Array(criteria).empty?
              return unjudged("No evaluation criteria provided",
                              "LLM judge requires :criteria parameter",
                              good_threshold, average_threshold)
            end

            if field_context.value.nil?
              return unjudged("Field held nothing to judge",
                              "LLM judge had no value to score",
                              good_threshold, average_threshold)
            end

            judged = judge(field_context, criteria, good_threshold, average_threshold, options[:model])
            result_from(judged, criteria, good_threshold, average_threshold)
          end

          private

          # @return [Hash] GEval's own result for this field
          def judge(field_context, criteria, good_threshold, average_threshold, model)
            GEval.new(criteria: Array(criteria),
                      good_threshold: good_threshold,
                      average_threshold: average_threshold)
                 .evaluate(field_context, model: model)
          end

          # GEval's result restated in this evaluator's own shape.
          #
          # +reasoning+ is the judge's chain of thought, so the explanation a
          # reader sees is the one the judge actually gave. The judge's model,
          # its token usage and its exchange travel with it: the call is billed
          # and leaves no tracing span, and a stand-in score is only legible as
          # one if the substitution is named.
          def result_from(judged, criteria, good_threshold, average_threshold)
            details = judged[:details] || {}

            {
              label: judged[:label],
              score: judged[:score],
              details: {
                criteria: criteria,
                reasoning: details[:chain_of_thought].to_s,
                criteria_evaluation: details[:criteria_evaluation],
                judge_model: details[:judge_model],
                judge_usage: details[:judge_usage],
                judge_prompt: details[:judge_prompt],
                judge_response: details[:judge_response],
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: "[#{judged[:label].to_s.upcase}] LLM judge: #{(judged[:score] * 100).round}%"
            }
          end

          # A result for the cases where there is nothing to ask a judge about.
          # Scored 0.0 rather than left unscored, so a check that can never be
          # answered reads as failing instead of as an average one.
          def unjudged(error, message, good_threshold, average_threshold)
            {
              label: "bad",
              score: 0.0,
              details: {
                error: error,
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: "[BAD] #{message}"
            }
          end
        end
      end
    end
  end
end
