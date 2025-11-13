# frozen_string_literal: true

require_relative "../dsl/evaluation_result"

module RAAF
  module Eval
    module DslEngine
      # Aggregates field evaluation results into final evaluation result
      class ResultAggregator
        class << self
          # Aggregate field results into evaluation result
          # @param field_results [Hash] Field name => evaluation result
          # @param config_name [Symbol] Configuration name
          # @param field_data [Hash] Original field data
          # @return [DSL::EvaluationResult] Aggregated result
          def aggregate(field_results, config_name, field_data)
            # Determine overall pass status (all fields must pass)
            passed = field_results.values.all? { |result| result[:passed] }

            # Build evaluation result
            DSL::EvaluationResult.new(
              passed: passed,
              field_results: field_results,
              configuration: config_name,
              field_data: field_data,
              metadata: {
                evaluated_at: Time.now,
                field_count: field_results.size
              }
            )
          end
        end
      end
    end
  end
end
