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
            # Determine status emoji and label
            if stat[:consistent]
              status_emoji = "✅"
              status_label = "GOOD"
            elsif stat[:range] <= @tolerance * 1.5
              status_emoji = "⚠️ "
              status_label = "AVERAGE"
            else
              status_emoji = "❌"
              status_label = "BAD"
            end

            # Format criterion name (capitalize and replace underscores)
            criterion_display = criterion.to_s.split('_').map(&:capitalize).join(' ')

            puts "#{status_emoji} #{criterion_display}: #{status_label}"
            puts "   #{field_label} Range: #{stat[:min]}-#{stat[:max]} (std dev: #{stat[:std_dev]})"
            puts "   Average: #{stat[:mean]}"
            puts "   Values: #{stat[:values].join(', ')}"
            puts ""
          end

          # Overall summary with good/average/bad breakdown
          total_criteria = stats.size
          good_count = stats.count { |_, s| s[:consistent] }
          average_count = stats.count { |_, s| !s[:consistent] && s[:range] <= @tolerance * 1.5 }
          bad_count = stats.count { |_, s| !s[:consistent] && s[:range] > @tolerance * 1.5 }
          consistency_rate = (good_count.to_f / total_criteria * 100).round(1)

          puts "-" * 80
          puts "Overall Consistency: #{good_count}/#{total_criteria} criteria (#{consistency_rate}%)"
          puts "Quality: ✅ #{good_count} good · ⚠️  #{average_count} average · ❌ #{bad_count} bad"
          puts "=" * 80
          puts ""
        end
      end
    end
  end
end
