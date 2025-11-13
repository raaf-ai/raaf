# frozen_string_literal: true

module RAAF
  module Eval
    module DslEngine
      # Compares evaluation results across multiple configurations
      class ConfigurationComparator
        class << self
          # Compare results across configurations
          # @param results [Hash] Configuration name => EvaluationResult
          # @param baseline_name [Symbol, nil] Baseline configuration name
          # @return [Hash] Comparison data structure
          def compare(results, baseline_name)
            baseline = results[baseline_name]
            return {} unless baseline

            comparisons = {}

            results.each do |config_name, result|
              next if config_name == baseline_name

              comparisons[config_name] = {
                field_deltas: compare_fields(baseline, result),
                overall_delta: calculate_overall_delta(baseline, result),
                improved_fields: identify_improvements(baseline, result),
                regressed_fields: identify_regressions(baseline, result)
              }
            end

            comparisons
          end

          private

          # Compare fields between two results
          # @param baseline [DSL::EvaluationResult] Baseline result
          # @param current [DSL::EvaluationResult] Current result
          # @return [Hash] Field deltas
          def compare_fields(baseline, current)
            baseline.field_results.map do |field_name, baseline_result|
              current_result = current.field_results[field_name]
              next unless current_result

              [field_name, {
                baseline_score: baseline_result[:score],
                current_score: current_result[:score],
                delta: calculate_delta(baseline_result[:score], current_result[:score]),
                delta_pct: calculate_percentage_delta(
                  baseline_result[:score],
                  current_result[:score]
                )
              }]
            end.compact.to_h
          end

          # Calculate overall delta between results
          # @param baseline [DSL::EvaluationResult] Baseline result
          # @param current [DSL::EvaluationResult] Current result
          # @return [Hash] Overall delta statistics
          def calculate_overall_delta(baseline, current)
            baseline_avg = average_score(baseline.field_results)
            current_avg = average_score(current.field_results)

            {
              baseline_avg: baseline_avg,
              current_avg: current_avg,
              delta: calculate_delta(baseline_avg, current_avg),
              delta_pct: calculate_percentage_delta(baseline_avg, current_avg)
            }
          end

          # Identify improved fields
          # @param baseline [DSL::EvaluationResult] Baseline result
          # @param current [DSL::EvaluationResult] Current result
          # @return [Array<Symbol>] Improved field names
          def identify_improvements(baseline, current)
            compare_fields(baseline, current).select do |_, deltas|
              deltas[:delta] > 0
            end.keys
          end

          # Identify regressed fields
          # @param baseline [DSL::EvaluationResult] Baseline result
          # @param current [DSL::EvaluationResult] Current result
          # @return [Array<Symbol>] Regressed field names
          def identify_regressions(baseline, current)
            compare_fields(baseline, current).select do |_, deltas|
              deltas[:delta] < 0
            end.keys
          end

          # Calculate average score across field results
          # @param field_results [Hash] Field results
          # @return [Float] Average score
          def average_score(field_results)
            scores = field_results.values.map { |r| r[:score] }.compact
            return 0.0 if scores.empty?

            scores.sum.to_f / scores.size
          end

          # Calculate absolute delta
          # @param baseline [Numeric] Baseline value
          # @param current [Numeric] Current value
          # @return [Float] Delta
          def calculate_delta(baseline, current)
            return 0.0 if baseline.nil? || current.nil?
            current.to_f - baseline.to_f
          end

          # Calculate percentage delta
          # @param baseline [Numeric] Baseline value
          # @param current [Numeric] Current value
          # @return [Float] Percentage delta
          def calculate_percentage_delta(baseline, current)
            return 0.0 if baseline.nil? || current.nil? || baseline.zero?

            ((current - baseline) / baseline * 100).round(2)
          end
        end
      end
    end
  end
end
