# frozen_string_literal: true

module RAAF
  module Eval
    module Metrics
      ##
      # StatisticalAnalyzer performs statistical analysis on evaluation results
      class StatisticalAnalyzer
        class << self
          ##
          # Calculate confidence interval
          # @param values [Array<Numeric>] Values to analyze
          # @param confidence_level [Float] Confidence level (default 0.95)
          # @return [Hash] Confidence interval
          def confidence_interval(values, confidence_level: 0.95)
            return { min: 0, max: 0, confidence: confidence_level } if values.empty?

            mean = values.sum.to_f / values.size
            std_dev = standard_deviation(values, mean)
            
            # Using t-distribution approximation
            margin = 1.96 * (std_dev / Math.sqrt(values.size))
            
            {
              min: mean - margin,
              max: mean + margin,
              confidence: confidence_level,
              mean: mean
            }
          end

          ##
          # Perform t-test for significance
          # @param baseline_values [Array<Numeric>] Baseline values
          # @param result_values [Array<Numeric>] Result values
          # @param significance_level [Float] Significance level (default 0.05)
          # @return [Hash] T-test results
          def t_test(baseline_values, result_values, significance_level: 0.05)
            return { significant: false, p_value: 1.0 } if baseline_values.empty? || result_values.empty?

            baseline_mean = baseline_values.sum.to_f / baseline_values.size
            result_mean = result_values.sum.to_f / result_values.size

            baseline_std = standard_deviation(baseline_values, baseline_mean)
            result_std = standard_deviation(result_values, result_mean)

            # Pooled standard deviation
            pooled_std = Math.sqrt(
              ((baseline_std**2 / baseline_values.size) + (result_std**2 / result_values.size))
            )

            # T-statistic
            t_stat = (result_mean - baseline_mean) / pooled_std
            
            # Approximate p-value (simplified)
            p_value = 2 * (1 - normal_cdf(t_stat.abs))

            {
              significant: p_value < significance_level,
              p_value: p_value.round(4),
              t_statistic: t_stat.round(4),
              baseline_mean: baseline_mean.round(4),
              result_mean: result_mean.round(4)
            }
          end

          ##
          # Calculate effect size (Cohen's d)
          # @param baseline_values [Array<Numeric>] Baseline values
          # @param result_values [Array<Numeric>] Result values
          # @return [Hash] Effect size
          def effect_size(baseline_values, result_values)
            return { cohens_d: 0.0, interpretation: "none" } if baseline_values.empty? || result_values.empty?

            baseline_mean = baseline_values.sum.to_f / baseline_values.size
            result_mean = result_values.sum.to_f / result_values.size

            baseline_std = standard_deviation(baseline_values, baseline_mean)
            result_std = standard_deviation(result_values, result_mean)

            # Pooled standard deviation
            pooled_std = Math.sqrt((baseline_std**2 + result_std**2) / 2)

            cohens_d = (result_mean - baseline_mean) / pooled_std

            {
              cohens_d: cohens_d.round(3),
              interpretation: interpret_effect_size(cohens_d)
            }
          end

          private

          def standard_deviation(values, mean)
            return 0.0 if values.size < 2

            variance = values.sum { |v| (v - mean)**2 } / (values.size - 1)
            Math.sqrt(variance)
          end

          def normal_cdf(x)
            # Approximate normal CDF using error function approximation
            (1.0 + Math.erf(x / Math.sqrt(2.0))) / 2.0
          end

          def interpret_effect_size(cohens_d)
            d = cohens_d.abs
            case d
            when 0...0.2 then "negligible"
            when 0.2...0.5 then "small"
            when 0.5...0.8 then "medium"
            else "large"
            end
          end
        end
      end
    end
  end
end
