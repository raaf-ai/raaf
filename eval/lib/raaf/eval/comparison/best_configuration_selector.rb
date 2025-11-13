# frozen_string_literal: true

module RAAF
  module Eval
    module Comparison
      # Selects best overall configuration based on improvements and regressions
      class BestConfigurationSelector
        # Select best configuration
        # @param improvements [Hash] Improvements by configuration
        # @param regressions [Hash] Regressions by configuration
        # @return [Symbol, nil] Best configuration name
        def self.select(improvements, regressions)
          # Get all configuration names
          all_configs = (improvements.keys + regressions.keys).uniq

          # Calculate improvement score for each configuration
          config_scores = all_configs.each_with_object({}) do |config_name, scores|
            improvement_count = improvements[config_name]&.size || 0
            regression_count = regressions[config_name]&.size || 0

            scores[config_name] = {
              improvements: improvement_count,
              regressions: regression_count,
              net_score: improvement_count - regression_count
            }
          end

          # Sort by net score descending, then by regressions ascending, then alphabetically
          config_scores.sort_by do |config_name, scores|
            [-scores[:net_score], scores[:regressions], config_name.to_s]
          end.first&.first
        end
      end
    end
  end
end
