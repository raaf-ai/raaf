# frozen_string_literal: true

require_relative "progress_event"

module RAAF
  module Eval
    module DslEngine
      # Emits progress events at key evaluation milestones
      # Coordinates with CallbackManager and ProgressCalculator
      class EventEmitter
        # Initialize event emitter
        # @param callback_manager [CallbackManager] Manages progress callbacks
        # @param progress_calculator [ProgressCalculator] Calculates progress percentages
        def initialize(callback_manager, progress_calculator)
          @callback_manager = callback_manager
          @progress_calculator = progress_calculator
          @start_time = nil
        end

        # Emit evaluation start event
        # @param metadata [Hash] Start event metadata
        def emit_start(metadata = {})
          @start_time = Time.now

          event = ProgressEvent.new(
            type: :start,
            progress: 0.0,
            status: :running,
            metadata: metadata
          )

          @callback_manager.invoke_callbacks(event)
        end

        # Emit configuration start event
        # @param config_name [Symbol] Configuration name
        # @param config_index [Integer] Zero-based configuration index
        # @param total_configs [Integer] Total number of configurations
        # @param config_params [Hash] Configuration parameters
        def emit_config_start(config_name, config_index, total_configs, config_params = {})
          progress = @progress_calculator.config_start_progress(config_index, total_configs)

          event = ProgressEvent.new(
            type: :config_start,
            progress: progress,
            status: :running,
            metadata: {
              configuration_name: config_name,
              configuration_index: config_index,
              total_configurations: total_configs,
              configuration_params: config_params
            }
          )

          @callback_manager.invoke_callbacks(event)
        end

        # Emit evaluator start event
        # @param config_name [Symbol] Configuration name
        # @param field_name [Symbol] Field being evaluated
        # @param evaluator_name [Symbol] Evaluator name
        # @param evaluator_index [Integer] Zero-based evaluator index
        # @param total_evaluators [Integer] Total evaluators for field
        def emit_evaluator_start(config_name, field_name, evaluator_name, evaluator_index, total_evaluators)
          progress = @progress_calculator.evaluator_progress(evaluator_index, total_evaluators)

          event = ProgressEvent.new(
            type: :evaluator_start,
            progress: progress,
            status: :running,
            metadata: {
              configuration_name: config_name,
              field_name: field_name,
              evaluator_name: evaluator_name,
              evaluator_index: evaluator_index,
              total_evaluators_for_field: total_evaluators
            }
          )

          @callback_manager.invoke_callbacks(event)
        end

        # Emit evaluator end event
        # @param config_name [Symbol] Configuration name
        # @param field_name [Symbol] Field that was evaluated
        # @param evaluator_name [Symbol] Evaluator name
        # @param result [Hash] Evaluator result with :passed and :score
        # @param duration_ms [Float] Evaluation duration in milliseconds
        def emit_evaluator_end(config_name, field_name, evaluator_name, result, duration_ms)
          status = result[:passed] ? :completed : :failed

          event = ProgressEvent.new(
            type: :evaluator_end,
            progress: @progress_calculator.current_progress,
            status: status,
            metadata: {
              configuration_name: config_name,
              field_name: field_name,
              evaluator_name: evaluator_name,
              evaluator_result: { passed: result[:passed], score: result[:score] },
              duration_ms: duration_ms
            }
          )

          @callback_manager.invoke_callbacks(event)
        end

        # Emit configuration end event
        # @param config_name [Symbol] Configuration name
        # @param result [Object] Configuration result with #passed? and #aggregate_score
        # @param evaluators_run [Integer] Number of evaluators executed
        def emit_config_end(config_name, result, evaluators_run)
          duration_ms = calculate_duration_ms

          event = ProgressEvent.new(
            type: :config_end,
            progress: @progress_calculator.current_progress,
            status: result.passed? ? :completed : :failed,
            metadata: {
              configuration_name: config_name,
              configuration_result: {
                passed: result.passed?,
                aggregate_score: result.aggregate_score
              },
              duration_ms: duration_ms,
              evaluators_run: evaluators_run
            }
          )

          @callback_manager.invoke_callbacks(event)
        end

        # Emit evaluation end event
        # @param configs_completed [Integer] Number of configurations completed
        # @param total_evaluators_run [Integer] Total evaluators executed
        # @param overall_passed [Boolean] Whether evaluation passed overall
        def emit_end(configs_completed, total_evaluators_run, overall_passed)
          total_duration_ms = calculate_duration_ms

          event = ProgressEvent.new(
            type: :end,
            progress: 100.0,
            status: overall_passed ? :completed : :failed,
            metadata: {
              total_duration_ms: total_duration_ms,
              configurations_completed: configs_completed,
              total_evaluators_run: total_evaluators_run,
              overall_passed: overall_passed
            }
          )

          @callback_manager.invoke_callbacks(event)
        end

        private

        # Calculate duration since start in milliseconds
        # @return [Float] Duration in milliseconds
        def calculate_duration_ms
          return 0.0 unless @start_time

          ((Time.now - @start_time) * 1000).round(2)
        end
      end
    end
  end
end
