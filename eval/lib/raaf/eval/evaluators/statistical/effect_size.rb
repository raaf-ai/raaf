# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Statistical
        # Evaluates practical significance via effect size
        class EffectSize
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :effect_size

          # Evaluate effect size
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :cohen_d (default 0.5 for medium effect)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            min_cohen_d = options[:cohen_d] || 0.5
            good_threshold = options[:good_threshold] || 0.8
            average_threshold = options[:average_threshold] || 0.6

            # Expect value to be a hash with statistical data
            data = field_context.value

            unless data.is_a?(Hash)
              return {
                label: "bad",
                score: 0.0,
                details: {
                  error: "Expected hash with statistical data",
                  threshold_good: good_threshold,
                  threshold_average: average_threshold
                },
                message: "[BAD] Invalid input: expected statistical data hash"
              }
            end

            # Calculate or extract Cohen's d
            cohen_d = data[:cohen_d] || calculate_cohen_d(data)

            unless cohen_d
              return {
                label: "bad",
                score: 0.0,
                details: {
                  error: "Unable to calculate effect size",
                  threshold_good: good_threshold,
                  threshold_average: average_threshold
                },
                message: "[BAD] Cannot calculate Cohen's d from provided data"
              }
            end

            score = calculate_score(cohen_d.abs, min_cohen_d)
            label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)

            {
              label: label,
              score: score,
              details: {
                cohen_d: cohen_d.round(3),
                min_cohen_d: min_cohen_d,
                effect_size_interpretation: interpret_effect_size(cohen_d.abs),
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: "[#{label.upcase}] Cohen's d: #{cohen_d.round(3)} (#{interpret_effect_size(cohen_d.abs)}, min: #{min_cohen_d})"
            }
          end

          private

          def calculate_cohen_d(data)
            return nil unless data[:control] && data[:treatment]
            
            control = data[:control]
            treatment = data[:treatment]
            
            return nil if control.empty? || treatment.empty?
            
            control_mean = calculate_mean(control)
            treatment_mean = calculate_mean(treatment)
            pooled_std = calculate_pooled_std(control, treatment)
            
            return nil if pooled_std == 0
            
            (treatment_mean - control_mean) / pooled_std
          end

          def calculate_mean(values)
            values.sum.to_f / values.size
          end

          def calculate_pooled_std(group1, group2)
            mean1 = calculate_mean(group1)
            mean2 = calculate_mean(group2)
            
            var1 = group1.sum { |v| (v - mean1)**2 } / (group1.size - 1)
            var2 = group2.sum { |v| (v - mean2)**2 } / (group2.size - 1)
            
            pooled_var = ((group1.size - 1) * var1 + (group2.size - 1) * var2) / 
                        (group1.size + group2.size - 2)
            
            Math.sqrt(pooled_var)
          end

          def interpret_effect_size(cohen_d_abs)
            if cohen_d_abs < 0.2
              "negligible"
            elsif cohen_d_abs < 0.5
              "small"
            elsif cohen_d_abs < 0.8
              "medium"
            else
              "large"
            end
          end

          def calculate_score(cohen_d_abs, min_cohen_d)
            return 1.0 if cohen_d_abs >= min_cohen_d * 1.5 # Strong effect
            return 0.0 if cohen_d_abs < min_cohen_d * 0.5

            # Linear scale
            (cohen_d_abs / (min_cohen_d * 1.5)).clamp(0, 1)
          end
        end
      end
    end
  end
end
