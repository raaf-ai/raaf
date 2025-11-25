# frozen_string_literal: true

module RAAF
  module Eval
    module DSL
      # Stores the configuration for an evaluator definition
      # Manages field selections, evaluator attachments, and progress callbacks
      #
      # @note History configuration has been removed in favor of database-driven
      #   configuration via EvaluationPolicy. See docs/CONTINUOUS_EVAL_MIGRATION.md.
      class EvaluatorConfig
        attr_reader :name, :selected_fields, :field_evaluators, :progress_callbacks,
                    :field_evaluator_sets

        # Initialize a new evaluator definition
        # @param name [String] Optional name for the evaluator
        def initialize(name: nil)
          @name = name
          @selected_fields = []
          @field_evaluators = {}
          @field_evaluator_sets = {}
          @progress_callbacks = []
        end

        # Add a field to be evaluated
        # @param path [String] The field path (supports dot notation)
        # @param as [String, nil] Optional alias for the field
        def add_field(path, as: nil)
          @selected_fields << { path: path, alias: as }
        end

        # Get a field by its path
        # @param path [String] The field path
        # @return [Hash, nil] The field configuration or nil if not found
        def get_field(path)
          @selected_fields.find { |field| field[:path] == path }
        end

        # Get a field by its alias
        # @param alias_name [String] The alias name
        # @return [Hash, nil] The field configuration or nil if not found
        def get_field_by_alias(alias_name)
          @selected_fields.find { |field| field[:alias] == alias_name }
        end

        # Add evaluator configuration for a field
        # @param field_name [String] The field name to evaluate
        # @param config [Hash] The evaluator configuration
        def add_field_evaluator(field_name, config)
          @field_evaluators[field_name] = config
        end

        # Get evaluator configuration for a field
        # @param field_name [String] The field name
        # @return [Hash, nil] The evaluator configuration or nil if not found
        def get_field_evaluator(field_name)
          @field_evaluators[field_name]
        end

        # Add a progress callback
        # @param block [Proc] The callback block to execute on progress events
        def add_progress_callback(&block)
          @progress_callbacks << block if block_given?
        end

        # Trigger progress callbacks with an event
        # @param event [Hash] The progress event data
        def trigger_progress(event)
          @progress_callbacks.each do |callback|
            callback.call(event)
          end
        end

        # @deprecated History configuration has been removed.
        #   Use database-backed EvaluationPolicy instead.
        #   See docs/CONTINUOUS_EVAL_MIGRATION.md for migration instructions.
        #
        # @raise [RAAF::Eval::DeprecatedDSLError] Always raises when called
        def configure_history(_config)
          raise RAAF::Eval::DeprecatedDSLError.new("configure_history")
        end

        # Define multiple evaluators for a field with combination logic
        # @param field_name [Symbol] The field name to evaluate
        # @yield Block for field evaluator DSL
        def evaluate_field(field_name, &block)
          field_set = FieldEvaluatorSet.new(field_name)

          # Create DSL context for field block
          field_dsl = FieldEvaluatorDSL.new(field_set)
          field_dsl.instance_eval(&block)

          @field_evaluator_sets[field_name] = field_set
        end

        # Get field evaluator set for a field
        # @param field_name [Symbol] The field name
        # @return [FieldEvaluatorSet, nil] The field evaluator set or nil if not found
        def get_field_evaluator_set(field_name)
          @field_evaluator_sets[field_name]
        end
      end

      # DSL context for defining field evaluators
      class FieldEvaluatorDSL
        def initialize(field_set)
          @field_set = field_set
        end

        # Add an evaluator to the field
        # @param evaluator_name [Symbol] The evaluator name
        # @param options [Hash] Options for the evaluator
        def evaluate_with(evaluator_name, **options)
          evaluator_alias = options.delete(:as)
          @field_set.add_evaluator(evaluator_name, options, evaluator_alias: evaluator_alias)
        end

        # Set combination strategy for field evaluators
        # @param strategy [Symbol, Proc] Strategy (:and, :or) or custom lambda
        def combine_with(strategy)
          @field_set.set_combination(strategy)
        end
      end
    end
  end
end
