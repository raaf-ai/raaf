# frozen_string_literal: true

module RAAF
  module Eval
    module Comparison
      # Calculates field-level deltas between baseline and other configurations
      class FieldDeltaCalculator
        # Calculate deltas for all fields across configurations
        # @param baseline_result [Object] Baseline evaluation result
        # @param other_results [Hash] Other configuration results
        # @return [Hash] Field deltas with baseline scores and configuration deltas
        def self.calculate(baseline_result, other_results)
          baseline_fields = baseline_result.field_results

          baseline_fields.each_with_object({}) do |(field_name, baseline_field_result), deltas|
            deltas[field_name] = {
              baseline_score: baseline_field_result[:score],
              configurations: calculate_field_deltas(field_name, baseline_field_result, other_results)
            }
          end
        end

        # Calculate deltas for a specific field across configurations
        # @param field_name [Symbol] Field name
        # @param baseline_field_result [Hash] Baseline field result
        # @param other_results [Hash] Other configuration results
        # @return [Hash] Configuration deltas for this field
        def self.calculate_field_deltas(field_name, baseline_field_result, other_results)
          other_results.each_with_object({}) do |(config_name, config_result), config_deltas|
            field_result = config_result.field_results[field_name]

            config_deltas[config_name] = {
              score: field_result[:score],
              delta: calculate_absolute_delta(baseline_field_result[:score], field_result[:score]),
              delta_pct: calculate_percentage_delta(baseline_field_result[:score], field_result[:score]),
              passed: field_result[:passed]
            }
          end
        end
        private_class_method :calculate_field_deltas

        # Calculate absolute delta
        # @param baseline_score [Numeric] Baseline score
        # @param current_score [Numeric] Current score
        # @return [Float] Absolute delta rounded to 4 decimal places
        def self.calculate_absolute_delta(baseline_score, current_score)
          (current_score - baseline_score).round(4)
        end
        private_class_method :calculate_absolute_delta

        # Calculate percentage delta
        # @param baseline_score [Numeric] Baseline score
        # @param current_score [Numeric] Current score
        # @return [Float] Percentage delta rounded to 2 decimal places
        def self.calculate_percentage_delta(baseline_score, current_score)
          return 0.0 if baseline_score.zero?

          (((current_score - baseline_score).to_f / baseline_score) * 100).round(2)
        end
        private_class_method :calculate_percentage_delta
      end
    end
  end
end
