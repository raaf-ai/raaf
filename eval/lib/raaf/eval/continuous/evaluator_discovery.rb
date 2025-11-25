# frozen_string_literal: true

module RAAF
  module Eval
    module Continuous
      # Error raised when an unknown evaluator is requested
      class UnknownEvaluatorError < RAAF::Eval::Error; end

      ##
      # EvaluatorDiscovery provides access to evaluators registered in the DSL registry.
      # This enables the UI to show available evaluators for policy configuration and
      # allows the continuous evaluation system to dynamically build evaluator instances.
      #
      # It leverages the existing RAAF::Eval::DSL::EvaluatorRegistry singleton,
      # which contains both built-in evaluators (LLM judges, rule-based, statistical)
      # and custom evaluators defined in end-user applications.
      #
      # @example Discover available evaluators
      #   EvaluatorDiscovery.available_evaluators
      #   #=> [:quality_judge, :pii_detector, :latency_monitor, ...]
      #
      # @example Get evaluator details for UI display
      #   EvaluatorDiscovery.evaluator_details
      #   #=> [
      #   #     { name: "quality_judge", type: "llm_judge", description: "..." },
      #   #     { name: "pii_detector", type: "rule_based", description: "..." }
      #   #   ]
      #
      # @example Build evaluator from policy configuration
      #   config = { "name" => "quality_judge", "config" => { "criteria" => "accuracy" } }
      #   evaluator = EvaluatorDiscovery.build(config)
      #   result = evaluator.evaluate(span_data, nil)
      #
      # @see RAAF::Eval::DSL::EvaluatorRegistry Registry of all evaluators
      # @see EvaluationPolicy Uses discovery to validate evaluator configurations
      class EvaluatorDiscovery
        class << self
          ##
          # Returns all registered evaluator names from the DSL registry.
          #
          # @return [Array<Symbol>] List of evaluator names
          #
          # @example Get all available evaluator names
          #   EvaluatorDiscovery.available_evaluators
          #   #=> [:quality_judge, :accuracy_judge, :pii_detector, :latency_monitor]
          def available_evaluators
            RAAF::Eval::DSL::EvaluatorRegistry.instance.all_names
          end

          ##
          # Returns detailed information about each registered evaluator.
          # Used by the UI to display evaluator options with descriptions.
          #
          # @return [Array<Hash>] List of evaluator details with name, type, and description
          #
          # @example Get details for UI display
          #   details = EvaluatorDiscovery.evaluator_details
          #   details.first
          #   #=> {
          #   #     name: "quality_judge",
          #   #     class_name: "RAAF::Eval::DSL::Evaluators::LlmJudge",
          #   #     type: "llm_judge",
          #   #     description: "Evaluates output quality using LLM",
          #   #     configurable_options: ["criteria", "model"]
          #   #   }
          def evaluator_details
            available_evaluators.map do |name|
              evaluator_class = RAAF::Eval::DSL::EvaluatorRegistry.instance.get(name)
              build_evaluator_detail(name, evaluator_class)
            rescue RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError
              # Skip evaluators that fail to load
              nil
            end.compact
          end

          ##
          # Builds an evaluator instance from policy configuration
          # @param config [Hash] Evaluator configuration from policy
          # @return [Object] Evaluator instance
          # @raise [UnknownEvaluatorError] if evaluator not found
          def build(config)
            name = extract_name(config)
            options = extract_config(config)

            begin
              evaluator_class = RAAF::Eval::DSL::EvaluatorRegistry.instance.get(name.to_sym)
              evaluator_class.new(options)
            rescue RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError
              raise UnknownEvaluatorError, "Unknown evaluator: #{name}"
            end
          end

          ##
          # Returns evaluators grouped by type
          # @return [Hash<String, Array<Hash>>] Evaluators grouped by type
          def grouped_by_type
            evaluator_details.group_by { |detail| detail[:type] }
          end

          ##
          # Searches evaluators by name or description
          # @param query [String] Search query
          # @return [Array<Hash>] Matching evaluator details
          def search(query)
            return [] if query.blank?

            query_downcase = query.downcase
            evaluator_details.select do |detail|
              name_matches = detail[:name].to_s.downcase.include?(query_downcase)
              desc_matches = detail[:description].to_s.downcase.include?(query_downcase)
              name_matches || desc_matches
            end
          end

          ##
          # Get details for a specific evaluator
          # @param name [Symbol, String] Evaluator name
          # @return [Hash, nil] Evaluator details or nil if not found
          def get_details(name)
            evaluator_class = RAAF::Eval::DSL::EvaluatorRegistry.instance.get(name.to_sym)
            build_evaluator_detail(name, evaluator_class)
          rescue RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError
            nil
          end

          private

          def build_evaluator_detail(name, evaluator_class)
            {
              name: name.to_s,
              class_name: evaluator_class.name,
              type: determine_evaluator_type(evaluator_class),
              description: extract_description(evaluator_class),
              configurable_options: extract_configurable_options(evaluator_class)
            }
          end

          def determine_evaluator_type(evaluator_class)
            # Check if evaluator explicitly declares its type
            if evaluator_class.respond_to?(:evaluator_type)
              return evaluator_class.evaluator_type.to_s
            end

            # Infer type from class name/namespace
            class_name = evaluator_class.name.to_s
            if class_name.include?("LlmJudge") || class_name.include?("Llm::")
              "llm_judge"
            elsif class_name.include?("Statistical")
              "statistical"
            else
              "rule_based"
            end
          end

          def extract_description(evaluator_class)
            return evaluator_class.description if evaluator_class.respond_to?(:description)
            nil
          end

          def extract_configurable_options(evaluator_class)
            return evaluator_class.configurable_options if evaluator_class.respond_to?(:configurable_options)
            []
          end

          def extract_name(config)
            config[:name] || config["name"]
          end

          def extract_config(config)
            config[:config] || config["config"] || {}
          end
        end
      end
    end
  end
end
