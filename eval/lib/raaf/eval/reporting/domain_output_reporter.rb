# frozen_string_literal: true

module RAAF
  module Eval
    module Reporting
      # Console reporter for domain-specific output consistency analysis
      #
      # Displays criterion-level or group-level consistency statistics in a readable format
      #
      class DomainOutputReporter
        def initialize(aggregator, tolerance: 15)
          @aggregator = aggregator
          @tolerance = tolerance
        end

        # Generate formatted console output for criterion consistency
        #
        # @param field_name [Symbol, String] Field to analyze (e.g., :score)
        # @param field_label [String] Human-readable field label (e.g., "Score")
        def generate(field_name: :score, field_label: "Score")
          stats = @aggregator.grouped_consistency_stats(field_name, tolerance: @tolerance)

          return if stats.empty?

          puts ""
          puts "=" * 80
          puts "CRITERION-LEVEL CONSISTENCY ANALYSIS"
          puts "=" * 80
          puts ""
          puts "Tolerance: ±#{@tolerance} points"
          puts "Runs analyzed: #{@aggregator.runs.size}"
          puts ""

          # Sort criteria alphabetically for consistent output
          stats.sort_by { |k, _| k.to_s }.each do |criterion, stat|
            # Determine status emoji
            status = if stat[:consistent]
                       "✅"
                     elsif stat[:range] <= @tolerance * 1.5
                       "⚠️ "
                     else
                       "❌"
                     end

            # Format criterion name (capitalize and replace underscores)
            criterion_display = criterion.to_s.split('_').map(&:capitalize).join(' ')

            puts "#{status} #{criterion_display}"
            puts "   #{field_label} Range: #{stat[:min]}-#{stat[:max]} (std dev: #{stat[:std_dev]})"
            puts "   Average: #{stat[:mean]}"
            puts "   Values: #{stat[:values].join(', ')}"
            puts ""
          end

          # Overall summary
          total_criteria = stats.size
          consistent_criteria = stats.count { |_, s| s[:consistent] }
          consistency_rate = (consistent_criteria.to_f / total_criteria * 100).round(1)

          puts "-" * 80
          puts "Overall Consistency: #{consistent_criteria}/#{total_criteria} criteria (#{consistency_rate}%)"
          puts "=" * 80
          puts ""
        end
      end
    end
  end
end
