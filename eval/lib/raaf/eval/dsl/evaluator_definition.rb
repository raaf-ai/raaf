# frozen_string_literal: true

module RAAF
  module Eval
    module DSL
      # Module that provides class-level DSL for defining evaluators
      # Eliminates the need for `class << self` singleton pattern
      # Provides automatic caching and configuration building
      #
      # @example Basic usage
      #   class MyEvaluator
      #     include RAAF::Eval::DSL::EvaluatorDefinition
      #
      #     select 'output', as: :output
      #     evaluate_field :output do
      #       evaluate_with :semantic_similarity, threshold: 0.85
      #     end
      #   end
      #
      #   evaluator = MyEvaluator.evaluator  # Automatic caching
      module EvaluatorDefinition
        # Hook called when module is included in a class
        # Extends the class with ClassMethods and initializes configuration
        def self.included(base)
          base.extend(ClassMethods)
          base.instance_variable_set(:@_evaluator_config, {
            selections: [],
            field_evaluations: {},
            progress_callback: nil,
            history_options: {}
          })
        end

        # Class methods added to including class
        module ClassMethods
          # Select a field for evaluation with optional alias
          # @param path [String] Field path (supports dot notation)
          # @param as [Symbol] Alias for the field
          # @example
          #   select 'usage.total_tokens', as: :tokens
          def select(path, as:)
            @_evaluator_config[:selections] << { path: path, as: as }
          end

          # Define evaluators for a specific field
          # @param name [Symbol] Field name to evaluate
          # @yield Block for field evaluator DSL
          # @example
          #   evaluate_field :output do
          #     evaluate_with :semantic_similarity, threshold: 0.85
          #     combine_with :and
          #   end
          def evaluate_field(name, &block)
            @_evaluator_config[:field_evaluations][name] = block
          end

          # Register a progress callback
          # @yield Block that receives progress events
          # @example
          #   on_progress do |event|
          #     puts "#{event.status}: #{event.progress}%"
          #   end
          def on_progress(&block)
            @_evaluator_config[:progress_callback] = block
          end

          # Configure historical storage
          # @param options [Hash] History configuration options
          # @option options [Boolean] :baseline Enable baseline tracking
          # @option options [Integer] :last_n Number of recent runs to retain
          # @option options [Boolean] :auto_save Automatically save results
          # @option options [Integer] :retention_days Days to retain history
          # @option options [Integer] :retention_count Max number of runs to retain
          # @example
          #   history baseline: true, last_n: 10, auto_save: true
          def history(**options)
            @_evaluator_config[:history_options].merge!(options)
          end

          # Return cached evaluator or build new one from DSL configuration
          # @return [RAAF::Eval::Evaluator] The evaluator instance
          def evaluator
            @evaluator ||= build_evaluator_from_config
          end

          # Clear cached evaluator (useful for testing)
          # @return [nil]
          def reset_evaluator!
            @evaluator = nil
          end

          # Wrapper method for evaluator.evaluate to provide consistent API
          # @param span_data [Hash] Span data to evaluate
          # @param options [Hash] Additional options passed to evaluator
          # @return [RAAF::Eval::Result] Evaluation result
          def evaluate(span_data, **options)
            evaluator.evaluate(span_data, **options)
          end

          private

          # Build evaluator from stored DSL configuration
          # @return [RAAF::Eval::Evaluator] New evaluator instance
          def build_evaluator_from_config
            config = @_evaluator_config

            RAAF::Eval.define do
              # Apply field selections
              config[:selections].each do |selection|
                select selection[:path], as: selection[:as]
              end

              # Apply field evaluations
              config[:field_evaluations].each do |field_name, evaluation_block|
                evaluate_field field_name, &evaluation_block
              end

              # Apply progress callback
              on_progress(&config[:progress_callback]) if config[:progress_callback]

              # Apply history configuration
              if config[:history_options].any?
                history_opts = config[:history_options]
                history do
                  history_opts.each { |k, v| send(k, v) }
                end
              end
            end
          end
        end
      end
    end
  end
end
