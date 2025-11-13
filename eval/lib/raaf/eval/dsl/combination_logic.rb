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
        # All evaluators must pass for combined result to pass
        # @param evaluator_results [Array<Hash>] Array of evaluator results
        # @return [Hash] Combined result with :passed, :score, :details, :message
        def self.combine_and(evaluator_results)
          passed = evaluator_results.all? { |r| r[:passed] }
          score = evaluator_results.map { |r| r[:score] }.min || 0.0
          
          {
            passed: passed,
            score: score,
            details: merge_details(evaluator_results),
            message: "AND: #{evaluator_results.map { |r| r[:message] }.join('; ')}"
          }
        end

        # Combine evaluator results using OR logic
        # At least one evaluator must pass for combined result to pass
        # @param evaluator_results [Array<Hash>] Array of evaluator results
        # @return [Hash] Combined result with :passed, :score, :details, :message
        def self.combine_or(evaluator_results)
          passed = evaluator_results.any? { |r| r[:passed] }
          score = evaluator_results.map { |r| r[:score] }.max || 0.0
          
          # Use messages from passing evaluators if any, otherwise all messages
          messages = if passed
                       evaluator_results.select { |r| r[:passed] }
                     else
                       evaluator_results
                     end
          
          {
            passed: passed,
            score: score,
            details: merge_details(evaluator_results),
            message: "OR: #{messages.map { |r| r[:message] }.join('; ')}"
          }
        end

        # Combine evaluator results using custom lambda logic
        # @param evaluator_results [Hash] Hash of evaluator results keyed by alias
        # @param lambda_proc [Proc] Lambda that receives named results and returns combined result
        # @return [Hash] Combined result with :passed, :score, :details, :message
        def self.combine_lambda(evaluator_results, lambda_proc)
          # Execute lambda with named results
          combined = lambda_proc.call(evaluator_results)
          
          # Validate lambda result has required fields
          validate_lambda_result!(combined)
          
          combined
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
          required_fields = [:passed, :score, :details, :message]
          missing_fields = required_fields - result.keys
          
          return if missing_fields.empty?
          
          raise InvalidLambdaResultError,
                "Lambda result missing required fields: #{missing_fields.join(', ')}"
        end

        private_class_method :merge_details, :validate_lambda_result!
      end
    end
  end
end
