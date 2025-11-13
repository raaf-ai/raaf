# frozen_string_literal: true

require_relative "field_delta_calculator"
require_relative "ranking_engine"
require_relative "improvement_detector"
require_relative "best_configuration_selector"

module RAAF
  module Eval
    module Comparison
      # Structured comparison result with field deltas, rankings, and improvements/regressions
      class ComparisonResult
        attr_reader :baseline_name, :timestamp, :field_deltas, :rankings,
                    :improvements, :regressions, :best_configuration, :metadata

        # Initialize comparison result
        # @param baseline_name [Symbol] Baseline configuration name
        # @param field_results [Hash] Field results for all configurations
        # @param timestamp [Time] Comparison timestamp
        def initialize(baseline_name:, field_results:, timestamp: Time.now)
          @baseline_name = baseline_name
          @timestamp = timestamp
          @field_results = field_results

          calculate_comparison
        end

        # Convert comparison to hash
        # @return [Hash] Comparison data
        def to_h
          {
            baseline_name: baseline_name,
            timestamp: timestamp,
            field_deltas: field_deltas,
            rankings: rankings,
            improvements: improvements,
            regressions: regressions,
            best_configuration: best_configuration,
            metadata: metadata
          }
        end

        # Get ranking for specific field
        # @param field_name [Symbol] Field name
        # @return [Array<Symbol>, nil] Configuration names ranked by score
        def rank_by_field(field_name)
          rankings[field_name]
        end

        private

        # Calculate all comparison data
        def calculate_comparison
          baseline_result = @field_results[@baseline_name]
          other_results = @field_results.except(@baseline_name)

          @field_deltas = FieldDeltaCalculator.calculate(baseline_result, other_results)
          @rankings = RankingEngine.rank_all_fields(@field_deltas)
          @improvements = ImprovementDetector.detect_improvements(@field_deltas)
          @regressions = ImprovementDetector.detect_regressions(@field_deltas)
          @best_configuration = BestConfigurationSelector.select(@improvements, @regressions)
          @metadata = build_metadata
        end

        # Build comparison metadata
        # @return [Hash] Metadata hash
        def build_metadata
          {
            total_configurations: @field_results.size,
            total_fields: @field_deltas.size,
            comparison_timestamp: @timestamp
          }
        end
      end
    end
  end
end
