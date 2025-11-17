# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Statistical
        # Evaluates statistical significance
        class StatisticalSignificance
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :statistical_significance

          # Evaluate statistical significance
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :p_value (default 0.05)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            threshold_p_value = options[:p_value] || 0.05
            good_threshold = options[:good_threshold] || 0.8
            average_threshold = options[:average_threshold] || 0.6

            # Expect value to be a hash with test results
            test_data = field_context.value

            unless test_data.is_a?(Hash)
              return {
                label: "bad",
                score: 0.0,
                details: {
                  error: "Expected hash with test results",
                  threshold_good: good_threshold,
                  threshold_average: average_threshold
                },
                message: "[BAD] Invalid input: expected test results hash"
              }
            end

            # Extract or calculate p-value
            p_value = test_data[:p_value] || calculate_p_value(test_data)

            score = calculate_score(p_value, threshold_p_value)
            label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)

            {
              label: label,
              score: score,
              details: {
                p_value: p_value&.round(4),
                threshold: threshold_p_value,
                sample_size: test_data[:sample_size],
                effect_size: test_data[:effect_size],
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: p_value ? "[#{label.upcase}] P-value: #{p_value.round(4)} (threshold: #{threshold_p_value})" : "[BAD] Unable to calculate p-value"
            }
          end

          private

          def calculate_p_value(test_data)
            # Simplified p-value calculation
            # In production, would use proper statistical libraries
            
            return nil unless test_data[:control] && test_data[:treatment]
            
            control = test_data[:control]
            treatment = test_data[:treatment]
            
            # Simple approximation using z-test
            control_mean = calculate_mean(control)
            treatment_mean = calculate_mean(treatment)
            pooled_std = calculate_pooled_std(control, treatment)
            
            return nil if pooled_std == 0
            
            z_score = (treatment_mean - control_mean) / (pooled_std * Math.sqrt(2.0 / control.size))
            
            # Approximate p-value from z-score (two-tailed)
            2 * (1 - normal_cdf(z_score.abs))
          end

          def calculate_mean(values)
            return 0 if values.empty?
            values.sum.to_f / values.size
          end

          def calculate_pooled_std(group1, group2)
            return 0 if group1.empty? || group2.empty?
            
            mean1 = calculate_mean(group1)
            mean2 = calculate_mean(group2)
            
            var1 = group1.sum { |v| (v - mean1)**2 } / (group1.size - 1)
            var2 = group2.sum { |v| (v - mean2)**2 } / (group2.size - 1)
            
            pooled_var = ((group1.size - 1) * var1 + (group2.size - 1) * var2) / 
                        (group1.size + group2.size - 2)
            
            Math.sqrt(pooled_var)
          end

          def normal_cdf(z)
            # Approximation of normal CDF
            # In production, would use proper statistical library
            0.5 * (1 + Math.erf(z / Math.sqrt(2)))
          end

          def calculate_score(p_value, threshold)
            return 0.0 unless p_value
            return 1.0 if p_value <= threshold / 10
            return 0.0 if p_value >= threshold * 2

            1.0 - (p_value / (threshold * 2)).clamp(0, 1)
          end
        end
      end
    end
  end
end
