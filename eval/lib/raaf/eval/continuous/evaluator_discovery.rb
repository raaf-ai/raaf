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
          # Resets all caches. Useful for development and testing.
          # Forces re-discovery of custom evaluators on next access.
          #
          # @return [void]
          #
          # @example Reset caches after modifying evaluator files
          #   EvaluatorDiscovery.reset!
          def reset!
            @custom_evaluators_loaded = false
            RAAF::Eval::DSL::EvaluatorDefinition.reset_included_classes! if defined?(RAAF::Eval::DSL::EvaluatorDefinition)
          end

          ##
          # Returns all registered evaluator names from the DSL registry.
          # Automatically registers built-in evaluators if not already done.
          #
          # @return [Array<Symbol>] List of evaluator names
          #
          # @example Get all available evaluator names
          #   EvaluatorDiscovery.available_evaluators
          #   #=> [:quality_judge, :accuracy_judge, :pii_detector, :latency_monitor]
          def available_evaluators
            ensure_built_ins_registered
            RAAF::Eval::DSL::EvaluatorRegistry.instance.all_names
          end

          ##
          # Returns detailed information about each registered evaluator.
          # Includes both registry evaluators AND custom evaluators that included
          # EvaluatorDefinition but may not have explicit evaluator_name set.
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
            custom_evaluator_details
          end

          ##
          # Returns details for custom evaluators that included EvaluatorDefinition.
          # These are evaluators defined in end-user applications.
          #
          # @return [Array<Hash>] List of custom evaluator details
          def custom_evaluator_details
            # Ensure EvaluatorDefinition is loaded before accessing it
            ensure_evaluator_definition_loaded
            return [] unless defined?(RAAF::Eval::DSL::EvaluatorDefinition)

            # Load custom evaluators from configured paths
            load_custom_evaluators

            RAAF::Eval::DSL::EvaluatorDefinition.included_classes.filter_map do |klass|
              # Skip anonymous classes (no name)
              next unless klass.name

              # Use evaluator_name if set, otherwise derive from class name
              name = klass.evaluator_name || derive_name_from_class(klass)
              build_evaluator_detail(name, klass)
            rescue StandardError
              # Skip evaluators that fail to load
              nil
            end
          end

          ##
          # Builds an evaluator instance from policy configuration
          # @param config [Hash] Evaluator configuration from policy
          # @return [Object] Evaluator instance
          # @raise [UnknownEvaluatorError] if evaluator not found
          def build(config)
            ensure_built_ins_registered
            name = extract_name(config)
            options = extract_config(config)

            # First try registry (built-in evaluators)
            begin
              evaluator_class = RAAF::Eval::DSL::EvaluatorRegistry.instance.get(name.to_sym)

              # CRITICAL: Check if this is an EvaluatorDefinition-based class
              # These classes use class methods (including transform_span_data hooks)
              # and must be returned as CLASS, not instantiated!
              if evaluator_class.respond_to?(:span_transformer_block) ||
                 (defined?(RAAF::Eval::DSL::EvaluatorDefinition) &&
                  evaluator_class.included_modules.include?(RAAF::Eval::DSL::Evaluator))
                if defined?(RAAF.logger) && RAAF.logger.respond_to?(:info)
                  RAAF.logger.info "[EvaluatorDiscovery] Found EvaluatorDefinition-based class in registry: #{evaluator_class.name}"
                  RAAF.logger.info "[EvaluatorDiscovery] Has span_transformer_block? #{evaluator_class.respond_to?(:span_transformer_block) && evaluator_class.span_transformer_block.present?}"
                end
                return evaluator_class
              end

              # Standard registry evaluators: instantiate with options
              symbolized_options = options.transform_keys(&:to_sym)
              return evaluator_class.new(**symbolized_options)
            rescue RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError
              # Not in registry, try custom evaluators
            end

            # Try to find custom evaluator by name from EvaluatorDefinition.included_classes
            evaluator_class = find_custom_evaluator_by_name(name)
            if evaluator_class
              # Custom evaluators (EvaluatorDefinition) are class-based, return the class itself
              # They define field evaluations via DSL, not instance methods
              if defined?(RAAF.logger) && RAAF.logger.respond_to?(:info)
                RAAF.logger.info "[EvaluatorDiscovery] Returning custom evaluator CLASS: #{evaluator_class.name}"
                RAAF.logger.info "[EvaluatorDiscovery] Has span_transformer_block? #{evaluator_class.respond_to?(:span_transformer_block) && evaluator_class.span_transformer_block.present?}"
              end
              return evaluator_class
            end

            raise UnknownEvaluatorError, "Unknown evaluator: #{name}. " \
              "Available built-in: #{RAAF::Eval::DSL::EvaluatorRegistry.instance.all_names.take(5).join(', ')}... " \
              "Available custom: #{custom_evaluator_names.take(5).join(', ')}..."
          end

          ##
          # Find a custom evaluator class by its derived name
          # @param name [String, Symbol] The evaluator name (e.g., "eval_prospect_scoring")
          # @return [Class, nil] The evaluator class or nil if not found
          def find_custom_evaluator_by_name(name)
            ensure_evaluator_definition_loaded
            return nil unless defined?(RAAF::Eval::DSL::EvaluatorDefinition)

            load_custom_evaluators

            name_sym = name.to_sym
            RAAF::Eval::DSL::EvaluatorDefinition.included_classes.find do |klass|
              next unless klass.name

              # Check both explicit evaluator_name AND derived name
              # This handles cases where policy stores derived name (eval_prospect_scoring)
              # but evaluator declares explicit name (prospect_scoring)
              explicit_name = klass.evaluator_name.to_sym if klass.respond_to?(:evaluator_name) && klass.evaluator_name
              derived_name = derive_name_from_class(klass)

              explicit_name == name_sym || derived_name == name_sym
            end
          end

          ##
          # Get all custom evaluator names for error messages
          # @return [Array<Symbol>] List of custom evaluator names
          def custom_evaluator_names
            ensure_evaluator_definition_loaded
            return [] unless defined?(RAAF::Eval::DSL::EvaluatorDefinition)

            load_custom_evaluators

            RAAF::Eval::DSL::EvaluatorDefinition.included_classes.filter_map do |klass|
              next unless klass.name

              if klass.respond_to?(:evaluator_name) && klass.evaluator_name
                klass.evaluator_name.to_sym
              else
                derive_name_from_class(klass)
              end
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
            return [] if query.nil? || query.empty?

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
            ensure_built_ins_registered
            evaluator_class = RAAF::Eval::DSL::EvaluatorRegistry.instance.get(name.to_sym)
            build_evaluator_detail(name, evaluator_class)
          rescue RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError
            nil
          end

          private

          ##
          # Returns details for registry evaluators only
          # @return [Array<Hash>] List of registry evaluator details
          def registry_details
            available_evaluators.map do |name|
              evaluator_class = RAAF::Eval::DSL::EvaluatorRegistry.instance.get(name)
              build_evaluator_detail(name, evaluator_class)
            rescue RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError
              # Skip evaluators that fail to load
              nil
            end.compact
          end

          ##
          # Derives a snake_case evaluator name from a class name
          # @param klass [Class] The evaluator class
          # @return [Symbol] Derived evaluator name
          # @example
          #   derive_name_from_class(Eval::Prospect::Scoring) #=> :eval_prospect_scoring
          def derive_name_from_class(klass)
            klass.name
              .gsub("::", "_")
              .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .downcase
              .to_sym
          end

          ##
          # Ensures built-in evaluators are registered before any discovery operation.
          # Only registers built-ins if configuration allows it.
          # This is idempotent and safe to call multiple times.
          def ensure_built_ins_registered
            load_custom_evaluators
            return unless Continuous.configuration.register_built_in_evaluators

            RAAF::Eval::DSL::EvaluatorRegistry.instance.auto_register_built_ins
          end

          ##
          # Loads custom evaluator files from configured paths.
          # This is idempotent and safe to call multiple times.
          def load_custom_evaluators
            return if @custom_evaluators_loaded

            paths = Continuous.configuration.evaluator_paths
            return if paths.nil? || paths.empty?

            paths.each do |path|
              load_evaluators_from_path(path)
            end

            @custom_evaluators_loaded = true
          end

          ##
          # Ensures the EvaluatorDefinition module is loaded.
          # Uses require_relative to load it since it's in the same gem.
          def ensure_evaluator_definition_loaded
            return if defined?(RAAF::Eval::DSL::EvaluatorDefinition)

            # Use require_relative since this file is in the same gem
            require_relative "../dsl/evaluator_definition"
          rescue LoadError => e
            # Log the error for debugging
            RAAF.logger.warn "[EvaluatorDiscovery] Could not load EvaluatorDefinition: #{e.message}" if defined?(RAAF.logger)
          end

          ##
          # Loads all Ruby files from the given directory path.
          # @param path [String] Path to directory containing evaluator files
          def load_evaluators_from_path(path)
            return unless File.directory?(path)

            Dir.glob(File.join(path, "**", "*.rb")).each do |file|
              require file
            rescue LoadError, StandardError => e
              # Log but don't fail - some files might not be valid evaluators
              RAAF.logger.warn "[EvaluatorDiscovery] Failed to load #{file}: #{e.message}" if defined?(RAAF.logger)
            end
          end

          def build_evaluator_detail(name, evaluator_class)
            eval_type = determine_evaluator_type(evaluator_class)
            {
              name: name.to_s,
              class_name: evaluator_class.name,
              type: eval_type,
              description: extract_description(evaluator_class),
              configurable_options: extract_configurable_options(evaluator_class),
              uses_llm: eval_type == "llm_judge",
              agent_name: extract_agent_name(evaluator_class),
              checks: extract_evaluated_checks(evaluator_class)
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

          def extract_agent_name(evaluator_class)
            return evaluator_class.agent_name if evaluator_class.respond_to?(:agent_name)
            nil
          end

          def extract_evaluated_fields(evaluator_class)
            return evaluator_class.evaluated_fields if evaluator_class.respond_to?(:evaluated_fields)
            []
          end

          # Extract detailed check information including specific evaluator types
          # @param evaluator_class [Class] The evaluator class
          # @return [Array<Hash>] List of checks with field_name, evaluator_type, and check_type
          def extract_evaluated_checks(evaluator_class)
            # Try the new evaluated_checks method first (provides detailed info)
            if evaluator_class.respond_to?(:evaluated_checks)
              return evaluator_class.evaluated_checks
            end

            # Fall back to evaluated_fields for legacy evaluators
            if evaluator_class.respond_to?(:evaluated_fields)
              return evaluator_class.evaluated_fields.map do |field|
                {
                  field_name: field,
                  evaluator_type: :unknown,
                  check_type: :rule_based
                }
              end
            end

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
