# frozen_string_literal: true

require_relative "../dsl/field_context"
require_relative "span_extractor"
require_relative "result_aggregator"
require_relative "configuration_comparator"
require_relative "callback_manager"
require_relative "progress_calculator"
require_relative "event_emitter"

module RAAF
  module Eval
    module DslEngine
      # Main evaluation engine that executes evaluators on span data
      # Handles single and multi-configuration evaluations with progress tracking
      #
      # @note History configuration (auto_save, retention) has been removed.
      #   Evaluation results are now stored via the continuous evaluation system
      #   using EvaluationPolicy and ContinuousEvaluationResult.
      class Evaluator
        attr_reader :definition

        # Initialize evaluator with DSL definition
        # @param definition [Hash] Configuration from DSL::Builder
        def initialize(definition)
          @definition = definition
          @field_selector = definition[:field_selector]
          @evaluator_definition = definition[:evaluator_definition]

          # Initialize callback manager and register progress callbacks
          @callback_manager = CallbackManager.new
          (definition[:progress_callbacks] || []).each do |callback|
            @callback_manager.register(&callback)
          end

          @progress_calculator = nil  # Initialized per evaluation
          @event_emitter = nil        # Initialized per evaluation
        end

        # Execute evaluation on span data
        # @param span [Hash] The span data to evaluate
        # @param configuration [Symbol, nil] Configuration name for single-config evaluation
        # @param only_fields [Array<Symbol>, nil] If provided, only evaluate these fields
        # @yield Optional block for multi-configuration evaluation
        # @return [DSL::EvaluationResult] Evaluation results
        # @example Single configuration
        #   result = evaluator.evaluate(span, configuration: :baseline)
        # @example Filter specific fields
        #   result = evaluator.evaluate(span, only_fields: [:individual_scores, :reasoning_texts])
        # @example Multiple configurations
        #   result = evaluator.evaluate(span) do
        #     configuration :low_temp, temperature: 0.3
        #     configuration :high_temp, temperature: 1.0
        #     baseline :low_temp
        #   end
        def evaluate(span, configuration: nil, only_fields: nil)
          @only_fields = only_fields&.map(&:to_sym)
          if block_given?
            evaluate_multi_config(span, &Proc.new)
          else
            evaluate_single_config(span, configuration || :default)
          end
        end

        private

        # Execute evaluation for a single configuration
        # @param span [Hash] The span data
        # @param config_name [Symbol] Configuration name
        # @return [DSL::EvaluationResult] Single-config results
        def evaluate_single_config(span, config_name)
          # Initialize progress tracking for single config
          # Use filtered count if only_fields is specified
          total_evaluators = count_total_evaluators_filtered
          @progress_calculator = ProgressCalculator.new(1, @field_selector.fields.size, total_evaluators)
          @event_emitter = EventEmitter.new(@callback_manager, @progress_calculator)

          # Emit start event
          @event_emitter.emit_start(
            total_configurations: 1,
            total_fields: @field_selector.fields.size,
            total_evaluators: total_evaluators,
            has_baseline: false
          )

          # Emit config start
          @event_emitter.emit_config_start(config_name, 0, 1, {})

          # Extract selected fields from span
          # If only_fields is specified, only extract those fields (for efficiency and to avoid missing field errors)
          field_data = SpanExtractor.extract_fields(span, @field_selector, only_fields: @only_fields)

          # Create field contexts
          field_contexts = create_field_contexts(field_data, config_name, span)

          # Execute evaluators for each field with progress events
          field_results, evaluator_results = execute_field_evaluations(field_contexts, config_name)

          # Aggregate results
          result = ResultAggregator.aggregate(field_results, evaluator_results, config_name, field_data)

          # Emit config end
          @event_emitter.emit_config_end(config_name, result, total_evaluators)

          # Advance to next config (for progress calculation)
          @progress_calculator.advance_config

          # Emit end event
          @event_emitter.emit_end(1, total_evaluators, result.passed?)

          result
        end

        # Execute evaluation for multiple configurations
        # @param span [Hash] The span data
        # @yield Block with configuration DSL
        # @return [DSL::EvaluationResult] Multi-config results with comparison
        def evaluate_multi_config(span, &block)
          config_dsl = ConfigurationDSL.new
          config_dsl.instance_eval(&block)

          configurations = config_dsl.configurations
          baseline_name = config_dsl.baseline_name

          # Initialize progress tracking for multiple configs
          total_evaluators = count_total_evaluators
          @progress_calculator = ProgressCalculator.new(
            configurations.size,
            @field_selector.fields.size,
            total_evaluators
          )
          @event_emitter = EventEmitter.new(@callback_manager, @progress_calculator)

          # Emit start event
          @event_emitter.emit_start(
            total_configurations: configurations.size,
            total_fields: @field_selector.fields.size,
            total_evaluators: total_evaluators * configurations.size,
            has_baseline: !baseline_name.nil?
          )

          # Run evaluation for each configuration
          results = {}
          total_evaluators_run = 0

          configurations.each_with_index do |(name, params), index|
            # Emit config start
            @event_emitter.emit_config_start(name, index, configurations.size, params)

            # Extract fields and create contexts
            # If only_fields is specified, only extract those fields
            field_data = SpanExtractor.extract_fields(span, @field_selector, only_fields: @only_fields)
            field_contexts = create_field_contexts(field_data, name, span)

            # Execute evaluators for each field with progress events
            field_results, evaluator_results = execute_field_evaluations(field_contexts, name)

            # Aggregate results for this configuration
            result = ResultAggregator.aggregate(field_results, evaluator_results, name, field_data)
            results[name] = result

            # Emit config end
            @event_emitter.emit_config_end(name, result, total_evaluators)
            total_evaluators_run += total_evaluators

            # Advance to next config
            @progress_calculator.advance_config
          end

          # Compare configurations
          comparison = ConfigurationComparator.compare(results, baseline_name)

          # Determine overall pass status
          overall_passed = results.values.all?(&:passed?)

          # Emit end event
          @event_emitter.emit_end(configurations.size, total_evaluators_run, overall_passed)

          # Return result with comparison data
          DSL::EvaluationResult.new(
            field_results: results,
            comparison: comparison,
            baseline: baseline_name
          )
        end

        # Execute evaluators for all fields
        # @param field_contexts [Hash] Field name => FieldContext
        # @param config_name [Symbol] Configuration name for event emission
        # @return [Array<Hash, Hash>] [field_results, evaluator_results]
        #   field_results: Field name => combined evaluation result
        #   evaluator_results: Field name => { alias => individual result }
        def execute_field_evaluations(field_contexts, config_name)
          field_results = {}
          evaluator_results = {}
          evaluator_index = 0

          # Filter field evaluator sets if only_fields is specified
          field_sets_to_evaluate = if @only_fields.present?
            @evaluator_definition.field_evaluator_sets.select { |name, _| @only_fields.include?(name.to_sym) }
          else
            @evaluator_definition.field_evaluator_sets
          end

          total_field_sets = field_sets_to_evaluate.size  # Use filtered count

          field_sets_to_evaluate.each do |field_name, evaluator_set|
            field_context = field_contexts[field_name]
            next unless field_context # Skip if field not found

            # Emit single evaluator start event for the field evaluation
            # Use the first evaluator's name as representative
            evaluator_name = evaluator_set.evaluators.first[:name]

            @event_emitter.emit_evaluator_start(
              config_name,
              field_name,
              evaluator_name,
              evaluator_index,
              total_field_sets  # Pass total field sets, not current set size
            )

            # Execute the evaluator set and time it
            start_time = Time.now
            evaluation_result = evaluator_set.evaluate(field_context)
            duration_ms = ((Time.now - start_time) * 1000).round(2)

            # Extract combined and individual results from new return format
            # FieldEvaluatorSet.evaluate now returns { combined: ..., individual: {...} }
            combined_result = evaluation_result[:combined]
            individual_results = evaluation_result[:individual]

            # Store combined result for field_results (backward compatibility)
            field_results[field_name] = combined_result

            # Store individual results for evaluator_results (new feature)
            evaluator_results[field_name] = individual_results

            # Emit single evaluator end event for the field evaluation
            @event_emitter.emit_evaluator_end(
              config_name,
              field_name,
              evaluator_name,
              { passed: combined_result[:passed], score: combined_result[:score] },
              duration_ms
            )

            # Advance progress once per field evaluation (not per evaluator in set)
            @progress_calculator.advance_evaluator
            evaluator_index += 1
          end

          [field_results, evaluator_results]
        end

        # Create field contexts for extracted field data
        # @param field_data [Hash] Extracted field values
        # @param config_name [Symbol] Configuration name
        # @param full_span [Hash] Complete span data
        # @return [Hash] Field name => FieldContext
        def create_field_contexts(field_data, config_name, full_span)
          # Build context data with configuration
          context_data = full_span.merge(configuration: config_name)

          # Transform field data to field contexts
          # For fields with wildcards, we already have the extracted flat arrays
          # We'll create a simplified FieldContext that holds the pre-extracted value
          field_data.each_with_object({}) do |(field_path, value), contexts|
            # Get alias if defined
            alias_name = @field_selector.aliases.key(field_path)
            key = alias_name ? alias_name.to_sym : field_path.to_sym

            # Create a hash that contains the extracted value at the field path
            # This allows FieldContext to work with pre-extracted values
            field_result = context_data.merge(field_path => value)

            # Create FieldContext with the field path and the result containing the value
            contexts[key] = DSL::FieldContext.new(field_path, field_result)
          end
        end

        # Count total field evaluator sets (treating each set as one evaluation unit)
        # @return [Integer] Total number of field evaluator sets
        def count_total_evaluators
          @evaluator_definition.field_evaluator_sets.size
        end

        # Count total field evaluator sets respecting only_fields filter
        # @return [Integer] Number of field evaluator sets that will be evaluated
        def count_total_evaluators_filtered
          if @only_fields.present?
            @evaluator_definition.field_evaluator_sets.count { |name, _| @only_fields.include?(name.to_sym) }
          else
            count_total_evaluators
          end
        end
      end

      # DSL for multi-configuration evaluation
      class ConfigurationDSL
        attr_reader :configurations, :baseline_name

        def initialize
          @configurations = {}
          @baseline_name = nil
        end

        # Define a configuration
        # @param name [Symbol] Configuration name
        # @param params [Hash] Configuration parameters
        def configuration(name, **params)
          @configurations[name] = params
        end

        # Set baseline configuration
        # @param name [Symbol] Baseline configuration name
        def baseline(name)
          @baseline_name = name
        end
      end
    end
  end
end
