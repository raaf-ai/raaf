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
            individual_checks = details[:individual_checks] || details["individual_checks"]
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
              name = check[:name] || check["name"]
              value = check[:value] || check["value"]
              threshold = check[:threshold] || check["threshold"]
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
            return format_keyed_result(details) if details.key?(:items_compared) || details.key?("items_compared")

            tolerance = details[:tolerance] || details["tolerance"]
            return format_spread_result(details, tolerance) if tolerance

            cv = details[:coefficient_of_variation] || details["coefficient_of_variation"]
            max_cv = details[:max_std_dev] || details["max_std_dev"] || 0.1
            mean = details[:mean] || details["mean"]
            std_dev = details[:std_dev] || details["std_dev"]

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
            md << "| Mean | #{mean&.round(2) || "N/A"} | — | — |\n"
            md << "| Std Dev | #{std_dev&.round(2) || "N/A"} | — | — |\n"
            md << "\n"

            if status == "✗ Bad"
              md << "**Issue:** Score variation (CV #{(cv * 100).round(1)}%) exceeds the maximum "
              md << "allowed (#{(max_cv * 100).round(1)}%), indicating inconsistent behavior.\n"
            end

            md
          end

          # Format a per-item result as markdown
          # @param details [Hash] The evaluation details
          # @return [String] Markdown-formatted result
          def self.format_keyed_result(details)
            fetch = ->(name) { details[name] || details[name.to_s] }
            md = String.new("### Consistency Check\n\n")
            md << "#{fetch.call(:items_consistent)} of #{fetch.call(:items_compared)} items gave the same answer " \
                  "across #{fetch.call(:runs)} runs"
            md << " (tolerance: #{fetch.call(:tolerance)})" if fetch.call(:tolerance)
            md << ".\n\n"

            worst = fetch.call(:worst_items) || []
            return md if worst.empty?

            md << "| Item | Values | Score |\n"
            md << "|------|--------|------:|\n"
            worst.each do |item|
              key = item[:key] || item["key"]
              values = (item[:values] || item["values"]).map { |v| v.nil? ? "missing" : v }
              md << "| #{key} | #{values.join(", ")} | #{(item[:score] || item["score"]).round(2)} |\n"
            end
            md << "\n"
          end

          # Format a tolerance-based result as markdown
          # @param details [Hash] The evaluation details
          # @param tolerance [Numeric] The allowed spread, in the field's own units
          # @return [String] Markdown-formatted result
          def self.format_spread_result(details, tolerance)
            spread = details[:spread] || details["spread"]
            values = details[:values] || details["values"] || []
            threshold_good = details[:threshold_good] || details["threshold_good"] || 0.8
            threshold_average = details[:threshold_average] || details["threshold_average"] || 0.6
            score = spread <= tolerance ? 1.0 : (1.0 - ((spread - tolerance) / (tolerance * 2.0))).clamp(0.0, 1.0)
            status = if score >= threshold_good
                       "✓ Good"
                     elsif score >= threshold_average
                       "◐ Average"
                     else
                       "✗ Bad"
                     end

            md = String.new("### Consistency Check\n\n")
            md << "| Metric | Value | Threshold | Result |\n"
            md << "|--------|------:|----------:|--------|\n"
            md << "| Spread (max − min) | #{spread} | ≤#{tolerance} | #{status} |\n"
            md << "| Values | #{values.join(", ")} | — | — |\n"
            md << "\n"
            md
          end

          # Determine status for an individual value
          def self.determine_status_for_value(value, threshold)
            return "◐ Average" unless value && threshold

            min_threshold = threshold[:min] || threshold["min"]
            max_threshold = threshold[:max] || threshold["max"]
            good_min = threshold[:good_min] || threshold["good_min"] || min_threshold
            good_max = threshold[:good_max] || threshold["good_max"] || max_threshold

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

            min_val = threshold[:min] || threshold["min"]
            max_val = threshold[:max] || threshold["max"]

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
          # When each run is a Hash (item key => value, from a selection that
          # declares +key:+), every item is compared with itself across the runs
          # and the score is the mean of the items' own scores. An item missing
          # from one run scores 0.0: leaving it out is a different answer.
          #
          # With +tolerance:+ the check measures the spread (max - min) of the
          # values in the field's own units instead of the coefficient of
          # variation. Declare it for any score on a coarse or integer scale: the
          # CV divides by the mean, so on a 1-10 scale [1, 1, 2] reads as 35%
          # variation and fails a 10% ceiling, while [8, 8, 9] passes, although
          # both moved by the same single point. A spread within the tolerance
          # scores 1.0, falling linearly to 0.0 at three times the tolerance.
          #
          # @param options [Hash] Options including :std_dev (max CV, default 0.1)
          #   and :tolerance (allowed spread; replaces the CV when given)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            max_std_dev = options[:std_dev] || 0.1
            good_threshold = options[:good_threshold] || 0.8
            average_threshold = options[:average_threshold] || 0.6

            # Expect value to be an array of results from multiple runs
            values = field_context.value

            # Not a verdict about the agent. Reaching here means the check was
            # handed one run's value where it needs several, so it never saw the
            # thing it grades — and a score of 0.0 without the flag is stored as
            # the agent having answered badly. FieldEvaluatorSet#failure_result
            # sets the same top-level +error+ for an evaluator that raised, and
            # the results page, Ai::EvaluatorSmokeRun and the eval report all
            # read that key to tell a crash from a verdict.
            unless values.is_a?(Array) && !values.empty?
              return {
                label: "bad",
                score: 0.0,
                error: true,
                details: {
                  error: "Expected array of values from multiple runs",
                  threshold_good: good_threshold,
                  threshold_average: average_threshold
                },
                message: "[ERROR] Invalid input: expected array of values"
              }
            end

            tolerance = options[:tolerance]
            if values.all?(Hash)
              return evaluate_keyed(values, tolerance: tolerance, max_std_dev: max_std_dev,
                                            good_threshold: good_threshold, average_threshold: average_threshold)
            end

            if tolerance
              return evaluate_spread(values, tolerance, good_threshold: good_threshold,
                                                        average_threshold: average_threshold)
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

          # How many of the least consistent items a keyed result names.
          WORST_ITEMS_REPORTED = 3

          private

          def evaluate_keyed(runs, tolerance:, max_std_dev:, good_threshold:, average_threshold:)
            item_keys = runs.flat_map(&:keys).map(&:to_s).uniq
            items = item_keys.map do |item_key|
              values = runs.map { |run| run[item_key] || run[item_key.to_sym] }
              { key: item_key, values: values, score: keyed_item_score(values, tolerance, max_std_dev) }
            end
            return keyed_result_without_items(good_threshold, average_threshold) if items.empty?

            score = (items.sum { |item| item[:score] } / items.size).round(4)
            label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)
            consistent = items.count { |item| item[:score] >= 1.0 }
            missing = items.count { |item| item[:values].any?(&:nil?) }
            worst = items.select { |item| item[:score] < 1.0 }.min_by(WORST_ITEMS_REPORTED) { |item| item[:score] }

            message = "[#{label.upcase}] #{consistent} of #{items.size} items consistent across #{runs.size} runs"
            message << " (tolerance: #{tolerance})" if tolerance
            message << "; worst #{worst.first[:key]} #{worst.first[:values].inspect}" if worst.any?

            {
              label: label,
              score: score,
              details: {
                runs: runs.size,
                items_compared: items.size,
                items_consistent: consistent,
                items_missing_from_a_run: missing,
                worst_items: worst,
                tolerance: tolerance,
                max_std_dev: tolerance ? nil : max_std_dev,
                threshold_good: good_threshold,
                threshold_average: average_threshold
              }.compact,
              message: message
            }
          end

          def keyed_item_score(values, tolerance, max_std_dev)
            return 0.0 if values.any?(&:nil?)

            numeric = values.map { |v| v.is_a?(Numeric) ? v : v.to_s.length }
            if tolerance
              calculate_spread_score((numeric.max - numeric.min).round(3), tolerance)
            else
              mean = numeric.sum.to_f / numeric.size
              cv = mean.zero? ? 0 : calculate_std_dev(numeric) / mean.abs
              calculate_score(cv, max_std_dev)
            end
          end

          def keyed_result_without_items(good_threshold, average_threshold)
            {
              label: "bad",
              score: 0.0,
              details: {
                error: "No item appeared in any run",
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: "[BAD] Invalid input: no items to compare across runs"
            }
          end

          def evaluate_spread(values, tolerance, good_threshold:, average_threshold:)
            numeric_values = values.map { |v| v.is_a?(Numeric) ? v : v.to_s.length }
            spread = (numeric_values.max - numeric_values.min).round(3)
            score = calculate_spread_score(spread, tolerance)
            label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)

            {
              label: label,
              score: score,
              details: {
                values: values,
                mean: calculate_mean(values).round(3),
                spread: spread,
                tolerance: tolerance,
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: "[#{label.upcase}] Consistency spread: #{spread} (tolerance: #{tolerance})"
            }
          end

          def calculate_spread_score(spread, tolerance)
            return 1.0 if spread <= tolerance
            return 0.0 if spread >= tolerance * 3

            (1.0 - ((spread - tolerance) / (tolerance * 2.0))).round(4)
          end

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

            1.0 - ((cv - (max_std_dev / 2)) / (max_std_dev * 1.5)).clamp(0, 1)
          end
        end
      end
    end
  end
end
