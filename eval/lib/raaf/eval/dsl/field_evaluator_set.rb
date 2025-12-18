# frozen_string_literal: true

module RAAF
  module Eval
    module DSL
      # Custom errors for field evaluator set
      class DuplicateAliasError < StandardError; end
      class InvalidCombinationStrategyError < StandardError; end

      # Container for multiple evaluators on a single field
      # Manages evaluator execution and result combination
      class FieldEvaluatorSet
        attr_reader :field_name, :evaluators, :combination_strategy, :result_formatter

        # Initialize a field evaluator set
        # @param field_name [Symbol] The field name being evaluated
        def initialize(field_name)
          @field_name = field_name
          @evaluators = []
          @combination_strategy = :and  # default
          @aliases = {}
          @result_formatter = nil
        end

        # Set a result formatter for this field
        # The block receives the field_result and span_data, and should return markdown.
        # @yield [field_result, span_data] Block that formats results as markdown
        # @yieldparam field_result [Hash] The evaluation result for this field
        # @yieldparam span_data [Hash] The original span data being evaluated
        # @yieldreturn [String] Markdown-formatted result description
        # @example
        #   result_format do |field_result, span_data|
        #     cv = field_result.dig(:details, :coefficient_of_variation)
        #     "### Consistency\n\n- **CV:** #{(cv * 100).round(1)}%"
        #   end
        def result_format(&block)
          @result_formatter = block
        end

        # Add an evaluator to the set
        # @param evaluator_name [Symbol] The evaluator name
        # @param options [Hash] Options to pass to the evaluator
        # @param evaluator_alias [Symbol, nil] Optional alias for this evaluator
        # @param display_name [String, nil] Human-readable name for this check
        # @param description [String, nil] Description of what this check validates
        # @raise [DuplicateAliasError] If alias is already used
        def add_evaluator(evaluator_name, options = {}, evaluator_alias: nil, display_name: nil, description: nil)
          alias_name = evaluator_alias || evaluator_name

          raise DuplicateAliasError, "Alias '#{alias_name}' is already used" if @aliases.key?(alias_name)

          @evaluators << {
            name: evaluator_name,
            alias: alias_name,
            options: options,
            display_name: display_name,
            description: description
          }
          @aliases[alias_name] = true
        end

        # Set the combination strategy
        # @param strategy [Symbol, Proc] Strategy (:and, :or) or custom lambda
        # @raise [InvalidCombinationStrategyError] If strategy is invalid
        def set_combination(strategy)
          validate_strategy!(strategy)
          @combination_strategy = strategy
          @explicit_combination_set = true
        end

        # Check if explicit combination was set (for validation)
        def explicit_combination?
          @explicit_combination_set ||= false
        end

        # Evaluate all evaluators and combine results
        # @param field_context [FieldContext] The field context to evaluate
        # @return [Hash] Combined evaluation result with individual evaluator results
        def evaluate(field_context)
          # Validate: warn if explicit combination with single evaluator
          if @evaluators.size == 1 && explicit_combination?
            warn "[RAAF::Eval] WARNING: combine_with #{@combination_strategy.inspect} specified for field '#{@field_name}' " \
                 "but only one evaluator exists. combine_with is meant for combining MULTIPLE evaluators. " \
                 "The combination strategy will be ignored and the evaluator result will be returned directly."
          end

          individual_results = execute_evaluators(field_context)
          combined_result = combine_results(individual_results)

          # Return both combined result and individual results
          # Individual results are keyed by alias for easy lookup
          {
            combined: combined_result,
            individual: individual_results
          }
        end

        private

        # Execute all evaluators in definition order
        # @param field_context [FieldContext] The field context
        # @return [Hash] Hash of results keyed by alias
        def execute_evaluators(field_context)
          @evaluators.each_with_object({}) do |eval_config, results|
            begin
              evaluator_class = RAAF::Eval.get_evaluator(eval_config[:name])
              evaluator = evaluator_class.new
              result = evaluator.evaluate(field_context, **eval_config[:options])
              results[eval_config[:alias]] = result
            rescue StandardError => e
              # Mark evaluator as failed but continue with others
              results[eval_config[:alias]] = {
                passed: false,
                score: 0.0,
                details: {
                  error: e.message,
                  error_class: e.class.name,
                  backtrace: e.backtrace&.first(3) || []
                },
                message: "Evaluator failed: #{e.message}"
              }
            end
          end
        end

        # Combine evaluator results using configured strategy
        # @param results [Hash] Hash of results keyed by alias
        # @return [Hash] Combined result
        def combine_results(results)
          # If only one evaluator, return result directly without combination
          # This preserves the :label field from custom evaluators
          if results.size == 1
            result = results.values.first
            # Transform :label to :passed for compatibility
            if result[:label] && !result.key?(:passed)
              result[:passed] = label_to_passed(result[:label])
            end
            return result
          end

          case @combination_strategy
          when :and
            CombinationLogic.combine_and(results.values)
          when :or
            CombinationLogic.combine_or(results.values)
          when Proc
            CombinationLogic.combine_lambda(results, @combination_strategy)
          else
            raise InvalidCombinationStrategyError, "Unknown strategy: #{@combination_strategy}"
          end
        end

        # Convert label string to passed boolean
        # @param label [String] The label ("good", "average", "bad")
        # @return [Boolean] True if label is "good" or "average", false otherwise
        def label_to_passed(label)
          %w[good average].include?(label.to_s.downcase)
        end

        # Validate combination strategy
        # @param strategy [Symbol, Proc] The strategy to validate
        # @raise [InvalidCombinationStrategyError] If strategy is invalid
        def validate_strategy!(strategy)
          return if [:and, :or].include?(strategy) || strategy.is_a?(Proc)
          
          raise InvalidCombinationStrategyError,
                "Strategy must be :and, :or, or a Proc, got: #{strategy.class}"
        end
      end
    end
  end
end
