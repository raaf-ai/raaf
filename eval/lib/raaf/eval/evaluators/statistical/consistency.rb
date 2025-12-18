# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Statistical
        # Evaluates consistency across multiple runs
        class Consistency
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :consistency

          # Format evaluation result as markdown
          # @param result [Hash] The evaluation result with :score and :details
          # @return [String] Markdown-formatted result
          def self.format_result(result)
            details = result[:details] || {}

            # Check if we have individual score checks
            individual_checks = details[:individual_checks] || details['individual_checks']
            if individual_checks && !individual_checks.empty?
              return format_individual_checks(details, individual_checks)
            end

            # Fall back to aggregate CV display
            format_aggregate_result(details)
          end

          # Format individual score checks as markdown table
          # @param details [Hash] The evaluation details
          # @param individual_checks [Array<Hash>] Array of individual check results
          # @return [String] Markdown-formatted result
          def self.format_individual_checks(details, individual_checks)
            md = String.new("### Consistency Check\n\n")
            md << "| Score | Value | Threshold | Result |\n"
            md << "|-------|------:|----------:|--------|\n"

            bad_scores = []

            individual_checks.each do |check|
              name = check[:name] || check['name']
              value = check[:value] || check['value']
              threshold = check[:threshold] || check['threshold']
              status = determine_status_for_value(value, threshold)

              md << "| #{name} | #{format_value(value)} | #{format_threshold(threshold)} | #{status} |\n"

              bad_scores << name if status == "✗ Bad"
            end

            md << "\n"

            if bad_scores.any?
              md << "**Issues:** #{bad_scores.length} score(s) outside acceptable range: "
              md << bad_scores.join(", ") << "\n"
            end

            md
          end

          # Format aggregate CV result as markdown
          # @param details [Hash] The evaluation details
          # @return [String] Markdown-formatted result
          def self.format_aggregate_result(details)
            cv = details[:coefficient_of_variation] || details['coefficient_of_variation']
            max_cv = details[:max_std_dev] || details['max_std_dev'] || 0.1
            mean = details[:mean] || details['mean']
            std_dev = details[:std_dev] || details['std_dev']

            return "No consistency data available" unless cv

            # Determine status based on CV relative to threshold
            status = if cv <= max_cv / 2
                       "✓ Good"
                     elsif cv <= max_cv
                       "◐ Average"
                     else
                       "✗ Bad"
                     end

            md = String.new("### Consistency Check\n\n")
            md << "| Metric | Value | Threshold | Result |\n"
            md << "|--------|------:|----------:|--------|\n"
            md << "| Coefficient of Variation | #{(cv * 100).round(1)}% | ≤#{(max_cv * 100).round(1)}% | #{status} |\n"
            md << "| Mean | #{mean&.round(2) || 'N/A'} | — | — |\n"
            md << "| Std Dev | #{std_dev&.round(2) || 'N/A'} | — | — |\n"
            md << "\n"

            if status == "✗ Bad"
              md << "**Issue:** Score variation (CV #{(cv * 100).round(1)}%) exceeds the maximum "
              md << "allowed (#{(max_cv * 100).round(1)}%), indicating inconsistent behavior.\n"
            end

            md
          end

          # Determine status for an individual value
          def self.determine_status_for_value(value, threshold)
            return "◐ Average" unless value && threshold

            min_threshold = threshold[:min] || threshold['min']
            max_threshold = threshold[:max] || threshold['max']
            good_min = threshold[:good_min] || threshold['good_min'] || min_threshold
            good_max = threshold[:good_max] || threshold['good_max'] || max_threshold

            if min_threshold && value < min_threshold
              "✗ Bad"
            elsif max_threshold && value > max_threshold
              "✗ Bad"
            elsif good_min && good_max && value >= good_min && value <= good_max
              "✓ Good"
            elsif min_threshold && max_threshold && value >= min_threshold && value <= max_threshold
              "◐ Average"
            else
              "◐ Average"
            end
          end

          # Format a value for display
          def self.format_value(value)
            case value
            when Float then value.round(2).to_s
            when Integer then value.to_s
            else value.to_s
            end
          end

          # Format a threshold for display
          def self.format_threshold(threshold)
            return "—" unless threshold

            min_val = threshold[:min] || threshold['min']
            max_val = threshold[:max] || threshold['max']

            if min_val && max_val
              "#{min_val}–#{max_val}"
            elsif min_val
              "≥#{min_val}"
            elsif max_val
              "≤#{max_val}"
            else
              "—"
            end
          end

          # Evaluate consistency of results
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :std_dev (default 0.1)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            max_std_dev = options[:std_dev] || 0.1
            good_threshold = options[:good_threshold] || 0.8
            average_threshold = options[:average_threshold] || 0.6

            # Expect value to be an array of results from multiple runs
            values = field_context.value

            unless values.is_a?(Array) && !values.empty?
              return {
                label: "bad",
                score: 0.0,
                details: {
                  error: "Expected array of values from multiple runs",
                  threshold_good: good_threshold,
                  threshold_average: average_threshold
                },
                message: "[BAD] Invalid input: expected array of values"
              }
            end

            # Calculate standard deviation
            std_dev = calculate_std_dev(values)
            mean = calculate_mean(values)

            # Normalize standard deviation by mean for coefficient of variation
            cv = mean == 0 ? 0 : std_dev / mean.abs

            score = calculate_score(cv, max_std_dev)
            label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)

            {
              label: label,
              score: score,
              details: {
                values: values,
                mean: mean.round(3),
                std_dev: std_dev.round(3),
                coefficient_of_variation: cv.round(3),
                max_std_dev: max_std_dev,
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: "[#{label.upcase}] Consistency CV: #{cv.round(3)} (max: #{max_std_dev})"
            }
          end

          private

          def calculate_mean(values)
            return 0 if values.empty?
            
            numeric_values = values.map { |v| v.is_a?(Numeric) ? v : v.to_s.length }
            numeric_values.sum.to_f / numeric_values.size
          end

          def calculate_std_dev(values)
            numeric_values = values.map { |v| v.is_a?(Numeric) ? v : v.to_s.length }
            mean = calculate_mean(values)
            
            variance = numeric_values.sum { |v| (v - mean)**2 } / numeric_values.size
            Math.sqrt(variance)
          end

          def calculate_score(cv, max_std_dev)
            return 1.0 if cv <= max_std_dev / 2
            return 0.0 if cv >= max_std_dev * 2

            1.0 - ((cv - max_std_dev / 2) / (max_std_dev * 1.5)).clamp(0, 1)
          end
        end
      end
    end
  end
end
