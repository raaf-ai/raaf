# frozen_string_literal: true

require_relative "field_selector"
require_relative "evaluator_config"

module RAAF
  module Eval
    module DSL
      # DSL Builder class that collects configuration from DSL blocks
      # Provides fluent interface for defining evaluators declaratively
      #
      # @note The `history do...end` DSL block has been removed in favor of
      #   database-driven configuration via EvaluationPolicy. See
      #   docs/CONTINUOUS_EVAL_MIGRATION.md for migration instructions.
      class Builder
        attr_reader :field_selector, :evaluator_definition, :progress_callbacks

        def initialize
          @field_selector = FieldSelector.new
          @evaluator_definition = EvaluatorConfig.new
          @progress_callbacks = []
        end

        # Select a field for evaluation with optional alias
        # @param field_path [String] The field path (supports dot notation)
        # @param as [Symbol, nil] Optional alias for the field
        # @example
        #   select 'usage.total_tokens', as: :tokens
        def select(field_path, as: nil)
          @field_selector.add_field(field_path, as: as)
        end

        # Define evaluators for a specific field
        # @param field_name [Symbol] The field name to evaluate
        # @yield Block for field evaluator DSL
        # @example
        #   evaluate_field :output do
        #     evaluate_with :semantic_similarity, threshold: 0.85
        #     combine_with :and
        #   end
        def evaluate_field(field_name, &block)
          @evaluator_definition.evaluate_field(field_name, &block)
        end

        # Register a progress callback
        # @yield Block that receives progress events
        # @example
        #   on_progress do |event|
        #     puts "#{event.status}: #{event.progress}%"
        #   end
        def on_progress(&block)
          @progress_callbacks << block if block_given?
        end

        # @deprecated The `history do...end` DSL block has been removed.
        #   Evaluation configuration is now managed via database-backed EvaluationPolicy.
        #   See docs/CONTINUOUS_EVAL_MIGRATION.md for migration instructions.
        #
        # @raise [RAAF::Eval::DeprecatedDSLError] Always raises when called
        # @example Migration
        #   # OLD (removed):
        #   history do
        #     auto_save true
        #     retention_days 30
        #   end
        #
        #   # NEW: Use EvaluationPolicy in database
        #   RAAF::Eval::Models::Continuous::EvaluationPolicy.create!(
        #     name: "my_policy",
        #     enabled: true,
        #     evaluators: [{ name: "my_evaluator" }],
        #     retention_days: 30
        #   )
        def history(&_block)
          raise RAAF::Eval::DeprecatedDSLError.new("history do...end")
        end

        # Build the final definition hash for the evaluator
        # @return [Hash] Configuration hash with all DSL settings
        def build_definition
          {
            field_selector: @field_selector,
            evaluator_definition: @evaluator_definition,
            progress_callbacks: @progress_callbacks,
            history_config: {} # Always empty - history is now database-driven
          }
        end
      end
    end
  end
end
