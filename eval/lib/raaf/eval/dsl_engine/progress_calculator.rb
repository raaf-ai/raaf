# frozen_string_literal: true

module RAAF
  module Eval
    module DslEngine
      # Calculates accurate progress percentages for evaluation execution
      # Handles multi-configuration and multi-evaluator progress tracking
      class ProgressCalculator
        # Initialize progress calculator
        # @param total_configurations [Integer] Total number of configurations
        # @param total_fields [Integer] Total number of fields
        # @param total_evaluators_per_field [Integer] Average evaluators per field
        def initialize(total_configurations, total_fields, total_evaluators_per_field)
          @total_configurations = total_configurations
          @total_fields = total_fields
          @total_evaluators_per_field = total_evaluators_per_field
          @current_config_index = 0
          @current_evaluator_index = 0
        end

        # Calculate progress at configuration start
        # @param config_index [Integer] Zero-based configuration index
        # @param total_configs [Integer] Total number of configurations
        # @return [Float] Progress percentage (0.0-100.0)
        def config_start_progress(config_index, total_configs)
          (config_index.to_f / total_configs * 100).round(2)
        end

        # Calculate progress for evaluator execution
        # @param evaluator_index [Integer] Zero-based evaluator index
        # @param total_evaluators [Integer] Total evaluators for current field
        # @return [Float] Progress percentage (0.0-100.0)
        def evaluator_progress(evaluator_index, total_evaluators)
          # Progress contribution of current configuration
          config_progress = (@current_config_index.to_f / @total_configurations)

          # Progress contribution of current evaluator within configuration
          evaluator_progress = (evaluator_index.to_f / total_evaluators) / @total_configurations

          # Combined progress as percentage
          ((config_progress + evaluator_progress) * 100).round(2)
        end

        # Advance to next configuration
        def advance_config
          @current_config_index += 1
        end

        # Advance to next evaluator
        def advance_evaluator
          @current_evaluator_index += 1
        end

        # Get current overall progress
        # @return [Float] Current progress percentage (0.0-100.0)
        def current_progress
          (@current_config_index.to_f / @total_configurations * 100).round(2)
        end
      end
    end
  end
end
