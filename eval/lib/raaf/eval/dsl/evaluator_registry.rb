# frozen_string_literal: true

require "singleton"
require_relative "evaluator"

module RAAF
  module Eval
    module DSL
      # Registry for managing evaluator classes
      # Provides thread-safe registration, lookup, and validation of evaluators
      class EvaluatorRegistry
        include Singleton

        # Error raised when evaluator is already registered
        class DuplicateEvaluatorError < StandardError; end

        # Error raised when evaluator class is invalid
        class InvalidEvaluatorError < StandardError; end

        # Error raised when evaluator is not found
        class UnregisteredEvaluatorError < StandardError; end

        def initialize
          @evaluators = {}
          @mutex = Mutex.new
          @built_ins_registered = false
        end

        # Register an evaluator class
        # @param name [Symbol, String] The evaluator name
        # @param evaluator_class [Class] The evaluator class
        # @raise [DuplicateEvaluatorError] if evaluator already registered
        # @raise [InvalidEvaluatorError] if evaluator class is invalid
        def register(name, evaluator_class)
          name_sym = name.to_sym

          @mutex.synchronize do
            # Check for duplicate registration
            if @evaluators.key?(name_sym)
              raise DuplicateEvaluatorError, 
                    "Evaluator '#{name_sym}' is already registered. Use a different name or unregister first."
            end

            # Validate evaluator class
            validate_evaluator_class!(name_sym, evaluator_class)

            # Register evaluator
            @evaluators[name_sym] = evaluator_class
          end

          evaluator_class
        end

        # Get an evaluator class by name
        # @param name [Symbol, String] The evaluator name
        # @return [Class] The evaluator class
        # @raise [UnregisteredEvaluatorError] if evaluator not found
        def get(name)
          name_sym = name.to_sym

          evaluator_class = @evaluators[name_sym]

          unless evaluator_class
            # Provide helpful suggestions
            suggestions = find_similar_names(name_sym)
            error_message = "Evaluator '#{name_sym}' not found in registry. "
            error_message += "Registered evaluators: #{all_names.join(', ')}" if all_names.any?
            error_message += "\nDid you mean: #{suggestions.join(', ')}" if suggestions.any?

            raise UnregisteredEvaluatorError, error_message
          end

          evaluator_class
        end

        # Check if an evaluator is registered
        # @param name [Symbol, String] The evaluator name
        # @return [Boolean] true if registered, false otherwise
        def registered?(name)
          @evaluators.key?(name.to_sym)
        end

        # Get all registered evaluator names
        # @return [Array<Symbol>] Array of evaluator names
        def all_names
          @evaluators.keys
        end

        # Auto-register all built-in evaluators
        # This method is idempotent and can be called multiple times safely
        def auto_register_built_ins
          return if @built_ins_registered

          @mutex.synchronize do
            return if @built_ins_registered

            require_relative "../evaluators/all_evaluators"

            # Register all built-in evaluators
            built_in_evaluators.each do |evaluator_class|
              name = evaluator_class.evaluator_name
              next if registered?(name) # Skip if already registered

              @evaluators[name] = evaluator_class
            end

            @built_ins_registered = true
          end
        end

        private

        # Validate that evaluator class is valid
        # @param name [Symbol] The registration name
        # @param evaluator_class [Class] The evaluator class
        # @raise [InvalidEvaluatorError] if evaluator is invalid
        def validate_evaluator_class!(name, evaluator_class)
          # Check if evaluator includes Evaluator module
          unless evaluator_class.include?(RAAF::Eval::DSL::Evaluator)
            raise InvalidEvaluatorError,
                  "Evaluator class must include RAAF::Eval::DSL::Evaluator module. " \
                  "Class #{evaluator_class} does not include the module."
          end

          # Check if evaluator_name matches registration name
          evaluator_name = evaluator_class.evaluator_name
          unless evaluator_name == name
            raise InvalidEvaluatorError,
                  "Evaluator class evaluator_name '#{evaluator_name}' must match " \
                  "registration name '#{name}'. Update the evaluator_name class method."
          end

          # Verify evaluate method exists
          unless evaluator_class.instance_methods.include?(:evaluate)
            raise InvalidEvaluatorError,
                  "Evaluator class must implement evaluate(field_context, **options) method. " \
                  "Class #{evaluator_class} does not have an evaluate method."
          end
        end

        # Find similar evaluator names using Levenshtein distance
        # @param name [Symbol] The name to find similarities for
        # @return [Array<Symbol>] Similar evaluator names
        def find_similar_names(name)
          name_str = name.to_s
          
          all_names.select do |registered_name|
            levenshtein_distance(name_str, registered_name.to_s) <= 2
          end.sort_by do |registered_name|
            levenshtein_distance(name_str, registered_name.to_s)
          end.take(3)
        end

        # Calculate Levenshtein distance between two strings
        # @param str1 [String] First string
        # @param str2 [String] Second string
        # @return [Integer] Levenshtein distance
        def levenshtein_distance(str1, str2)
          n = str1.length
          m = str2.length
          return m if n.zero?
          return n if m.zero?

          # Initialize distance matrix
          d = Array.new(n + 1) { Array.new(m + 1) }

          (0..n).each { |i| d[i][0] = i }
          (0..m).each { |j| d[0][j] = j }

          # Calculate distances
          (1..n).each do |i|
            (1..m).each do |j|
              cost = str1[i - 1] == str2[j - 1] ? 0 : 1

              d[i][j] = [
                d[i - 1][j] + 1,     # deletion
                d[i][j - 1] + 1,     # insertion
                d[i - 1][j - 1] + cost  # substitution
              ].min
            end
          end

          d[n][m]
        end

        # Get all built-in evaluator classes
        # @return [Array<Class>] Array of evaluator classes
        def built_in_evaluators
          [
            # Quality evaluators (1 - only SemanticSimilarity implemented)
            RAAF::Eval::Evaluators::Quality::SemanticSimilarity,
            # Note: Coherence, HallucinationDetection, Relevance are stubs (not yet implemented)

            # Performance evaluators (3)
            RAAF::Eval::Evaluators::Performance::TokenEfficiency,
            RAAF::Eval::Evaluators::Performance::Latency,
            RAAF::Eval::Evaluators::Performance::Throughput,

            # Regression evaluators (3)
            RAAF::Eval::Evaluators::Regression::NoRegression,
            RAAF::Eval::Evaluators::Regression::TokenRegression,
            RAAF::Eval::Evaluators::Regression::LatencyRegression,

            # Safety evaluators (3)
            RAAF::Eval::Evaluators::Safety::BiasDetection,
            RAAF::Eval::Evaluators::Safety::ToxicityDetection,
            RAAF::Eval::Evaluators::Safety::Compliance,

            # Statistical evaluators (3)
            RAAF::Eval::Evaluators::Statistical::Consistency,
            RAAF::Eval::Evaluators::Statistical::StatisticalSignificance,
            RAAF::Eval::Evaluators::Statistical::EffectSize,

            # Structural evaluators (3)
            RAAF::Eval::Evaluators::Structural::JsonValidity,
            RAAF::Eval::Evaluators::Structural::SchemaMatch,
            RAAF::Eval::Evaluators::Structural::FormatCompliance,

            # LLM evaluators (3)
            RAAF::Eval::Evaluators::LLM::LlmJudge,
            RAAF::Eval::Evaluators::LLM::QualityScore,
            RAAF::Eval::Evaluators::LLM::RubricEvaluation
          ]
        end
      end
    end
  end
end
