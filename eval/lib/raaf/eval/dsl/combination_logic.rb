# frozen_string_literal: true

module RAAF
  module Eval
    module DSL
      # Custom error for invalid lambda results
      class InvalidLambdaResultError < StandardError; end

      # Handles combination logic for multiple evaluators on a field
      # Supports AND, OR, and custom lambda combination strategies
      class CombinationLogic
        # Combine evaluator results using AND logic
        # The combined verdict is the weakest label any evaluator gave
        # @param evaluator_results [Array<Hash>] Array of evaluator results
        # @return [Hash] Combined result with :label, :score, :details, :message
        def self.combine_and(evaluator_results)
          label = weakest_label(evaluator_results)
          score = evaluator_results.map { |r| r[:score] }.min || 0.0

          {
            label: label,
            score: score,
            details: merge_details(evaluator_results),
            message: "AND: #{evaluator_results.map { |r| r[:message] }.join("; ")}"
          }
        end

        # Combine evaluator results using OR logic
        # The combined verdict is the strongest label any evaluator gave
        # @param evaluator_results [Array<Hash>] Array of evaluator results
        # @return [Hash] Combined result with :label, :score, :details, :message
        def self.combine_or(evaluator_results)
          label = strongest_label(evaluator_results)
          score = evaluator_results.map { |r| r[:score] }.max || 0.0

          # Speak for the evaluators that reached the combined verdict; when none did,
          # every message is part of the explanation.
          reached = evaluator_results.select { |r| r[:label] == label }
          messages = reached.empty? ? evaluator_results : reached

          {
            label: label,
            score: score,
            details: merge_details(evaluator_results),
            message: "OR: #{messages.map { |r| r[:message] }.join("; ")}"
          }
        end

        # Combine evaluator results using custom lambda logic
        # @param evaluator_results [Hash] Hash of evaluator results keyed by alias
        # @param lambda_proc [Proc] Lambda that receives named results and returns combined result
        # @return [Hash] Combined result with :label, :score, :details, :message
        def self.combine_lambda(evaluator_results, lambda_proc)
          # Execute lambda with named results
          combined = lambda_proc.call(evaluator_results)

          # Validate lambda result has required fields
          validate_lambda_result!(combined)

          combined
        end

        # Ordering of the three-tier labels, weakest first. Anything an evaluator reports
        # outside them counts as the weakest, so an unrecognised verdict never passes for
        # a good one.
        LABEL_ORDER = %w[bad average good].freeze

        # The weakest label any evaluator gave, which is what AND combines to
        # @param evaluator_results [Array<Hash>] Array of evaluator results
        # @return [String] Combined label
        def self.weakest_label(evaluator_results)
          return "bad" if evaluator_results.empty?

          evaluator_results.map { |r| LABEL_ORDER.index(r[:label]) || 0 }.min.then { |i| LABEL_ORDER[i] }
        end

        # The strongest label any evaluator gave, which is what OR combines to
        # @param evaluator_results [Array<Hash>] Array of evaluator results
        # @return [String] Combined label
        def self.strongest_label(evaluator_results)
          return "bad" if evaluator_results.empty?

          evaluator_results.map { |r| LABEL_ORDER.index(r[:label]) || 0 }.max.then { |i| LABEL_ORDER[i] }
        end

        # Merge details from multiple evaluator results
        # @param evaluator_results [Array<Hash>] Array of evaluator results
        # @return [Hash] Merged details hash
        def self.merge_details(evaluator_results)
          evaluator_results.each_with_object({}) do |result, merged|
            merged.merge!(result[:details] || {})
          end
        end

        # Validate that lambda result has all required fields
        # @param result [Hash] The lambda result to validate
        # @raise [InvalidLambdaResultError] If required fields are missing
        def self.validate_lambda_result!(result)
          required_fields = %i[label score details message]
          missing_fields = required_fields - result.keys

          return if missing_fields.empty?

          raise InvalidLambdaResultError,
                "Lambda result missing required fields: #{missing_fields.join(", ")}"
        end

        private_class_method :merge_details, :validate_lambda_result!, :weakest_label, :strongest_label
      end
    end
  end
end
