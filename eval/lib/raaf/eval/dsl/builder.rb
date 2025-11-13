# frozen_string_literal: true

require_relative "field_selector"
require_relative "evaluator_definition"

module RAAF
  module Eval
    module DSL
      # DSL Builder class that collects configuration from DSL blocks
      # Provides fluent interface for defining evaluators declaratively
      class Builder
        attr_reader :field_selector, :evaluator_definition, :progress_callbacks, :history_config

        def initialize
          @field_selector = FieldSelector.new
          @evaluator_definition = EvaluatorDefinition.new
          @progress_callbacks = []
          @history_config = default_history_config
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

        # Configure historical storage
        # @yield Block for history configuration DSL
        # @example
        #   history do
        #     auto_save true
        #     retention_days 30
        #   end
        def history(&block)
          history_dsl = HistoryDSL.new
          history_dsl.instance_eval(&block)
          @history_config = @history_config.merge(history_dsl.to_hash)
        end

        # Build the final definition hash for the evaluator
        # @return [Hash] Configuration hash with all DSL settings
        def build_definition
          {
            field_selector: @field_selector,
            evaluator_definition: @evaluator_definition,
            progress_callbacks: @progress_callbacks,
            history_config: @history_config
          }
        end

        private

        # Default history configuration
        # @return [Hash] Default history settings
        def default_history_config
          {
            auto_save: false,
            retention_days: nil,
            retention_count: nil,
            tags: {}
          }
        end
      end

      # DSL context for history configuration block
      class HistoryDSL
        def initialize
          @config = {}
        end

        # Enable or disable automatic result saving
        # @param value [Boolean] Whether to auto-save results
        def auto_save(value)
          @config[:auto_save] = value
        end

        # Set retention policy based on age
        # @param days [Integer] Number of days to retain results
        def retention_days(days)
          @config[:retention_days] = days
        end

        # Set retention policy based on count
        # @param count [Integer] Maximum number of results to keep
        def retention_count(count)
          @config[:retention_count] = count
        end

        # Add custom tags/metadata to evaluation runs
        # @param hash [Hash] Tag key-value pairs
        def tags(hash)
          @config[:tags] = hash
        end

        # Convert configuration to hash
        # @return [Hash] History configuration
        def to_hash
          @config
        end
      end
    end
  end
end
