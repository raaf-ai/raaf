# frozen_string_literal: true

module RAAF
  module Eval
    module DSL
      # Module that provides class-level DSL for defining evaluators
      # Eliminates the need for `class << self` singleton pattern
      # Provides automatic caching and configuration building
      #
      # Classes that include this module can use `evaluator_name :my_evaluator`
      # to auto-register with the EvaluatorRegistry, making them discoverable
      # in the continuous evaluation policy UI.
      #
      # @note The `history` DSL method has been removed in favor of
      #   database-driven configuration via EvaluationPolicy. See
      #   docs/CONTINUOUS_EVAL_MIGRATION.md for migration instructions.
      #
      # @example Basic usage with auto-registration
      #   class MyEvaluator
      #     include RAAF::Eval::DSL::EvaluatorDefinition
      #
      #     evaluator_name :my_evaluator  # Auto-registers with EvaluatorRegistry
      #
      #     select 'output', as: :output
      #     evaluate_field :output do
      #       evaluate_with :semantic_similarity, threshold: 0.85
      #     end
      #   end
      #
      #   evaluator = MyEvaluator.evaluator  # Automatic caching
      module EvaluatorDefinition
        # Thread-safe storage for tracking all classes that include this module
        @included_classes = []
        @mutex = Mutex.new

        class << self
          # Returns all classes that have included EvaluatorDefinition
          # @return [Array<Class>] Array of classes that included this module
          def included_classes
            @mutex.synchronize { @included_classes.dup }
          end

          # Clears the tracked classes (useful for testing)
          # @return [void]
          def reset_included_classes!
            @mutex.synchronize { @included_classes.clear }
          end
        end

        # Hook called when module is included in a class
        # Includes Evaluator interface and extends with ClassMethods
        def self.included(base)
          # Use safe logging in case RAAF.logger is not available during load
          safe_log = ->(msg) { RAAF.logger.info(msg) rescue puts(msg) }
          safe_log.call "[EvaluatorDefinition] Module included in: #{base.name}"
          safe_log.call "[EvaluatorDefinition] Setting up @_evaluator_config..."

          # Track all classes that include this module
          @mutex.synchronize { @included_classes << base }

          base.include(Evaluator) # Include interface contract for registry compatibility
          base.extend(ClassMethods)
          config = {
            selections: [],
            field_evaluations: {},
            progress_callback: nil,
            result_formatter: nil,
            span_transformer: nil
          }
          base.instance_variable_set(:@_evaluator_config, config)
          safe_log.call "[EvaluatorDefinition] @_evaluator_config set with object_id: #{config.object_id}"

          # Override Evaluator's evaluate method with delegation to DSL evaluator
          # This must be defined here (not as module method) because Evaluator
          # is added to ancestors before EvaluatorDefinition, so its evaluate
          # would take precedence otherwise.
          #
          # The continuous evaluation system calls evaluator_class.new.evaluate(...)
          # so we need an instance method that delegates to the class-level DSL evaluator.
          base.define_method(:evaluate) do |field_context, **options|
            self.class.evaluator.evaluate(field_context, **options)
          end
        end

        # Class methods added to including class
        module ClassMethods
          # Set evaluator name and auto-register with the EvaluatorRegistry
          # When called with a name, stores it and registers the class for discovery
          # in the continuous evaluation policy UI.
          #
          # @param name [Symbol, String, nil] The evaluator name for registry lookup
          # @return [Symbol, nil] The stored evaluator name
          # @example
          #   evaluator_name :my_custom_evaluator  # Registers with registry
          #   evaluator_name  # => :my_custom_evaluator (getter)
          def evaluator_name(name = nil)
            if name
              @evaluator_name = name.to_sym
              # Auto-register with registry for discoverability
              EvaluatorRegistry.instance.register(@evaluator_name, self)
              @evaluator_name
            else
              @evaluator_name
            end
          end

          # Declare which agent this evaluator is for
          # @param name [Symbol, String, nil] The agent name/class
          # @return [Symbol, String, nil] The stored agent name
          # @example
          #   for_agent "Prospect::Scoring"
          #   for_agent :prospect_scoring
          def for_agent(name = nil)
            if name
              @for_agent = name
            else
              @for_agent
            end
          end

          # Set or get a human-readable display name for the evaluator
          # This is used in the UI to identify the evaluator
          # @param name [String, nil] The display name
          # @return [String, nil] The stored display name
          # @example
          #   display_name "Prospect Scoring Evaluator"
          #   display_name  # => "Prospect Scoring Evaluator" (getter)
          def display_name(name = nil)
            if name
              @display_name = name
            else
              @display_name
            end
          end

          # Set or get a description for the evaluator
          # This is used in the UI to explain what this evaluator does
          # @param text [String, nil] The description text
          # @return [String, nil] The stored description
          # @example
          #   description "Evaluates prospect scoring agent outputs for quality, consistency, and regression"
          #   description  # => "Evaluates prospect scoring..." (getter)
          def description(text = nil)
            if text
              @description = text
            else
              @description
            end
          end

          # Returns the agent name this evaluator is for
          # First checks explicit declaration, then derives from class name
          # @return [String, nil] The agent name
          # @example
          #   # For Eval::Prospect::Scoring, returns "Prospect::Scoring"
          #   agent_name  # => "Prospect::Scoring"
          def agent_name
            return @for_agent.to_s if @for_agent

            # Derive from class name: Eval::Prospect::Scoring -> Prospect::Scoring
            derive_agent_name_from_class
          end

          # Returns the list of field names being evaluated (the checks)
          # @return [Array<Symbol>] List of field names with evaluations
          # @example
          #   evaluated_fields  # => [:individual_scores, :reasoning_texts, :tokens, :latency]
          def evaluated_fields
            @_evaluator_config[:field_evaluations].keys
          end

          # Returns detailed information about each check including specific evaluator types
          # @return [Array<Hash>] List of checks with field_name, evaluator_type, check_type, display_name, and description
          # @example
          #   evaluated_checks  # => [
          #     { field_name: :individual_scores, evaluator_type: :consistency, check_type: :statistical,
          #       display_name: "Score Consistency", description: "Verifies scoring is deterministic" },
          #     { field_name: :individual_scores, evaluator_type: :no_regression, check_type: :statistical },
          #     { field_name: :reasoning_texts, evaluator_type: :llm_judge, check_type: :llm_judge }
          #   ]
          def evaluated_checks
            checks = []
            @_evaluator_config[:field_evaluations].each do |field_name, block|
              # Build a temporary field set to extract evaluator info
              field_set = FieldEvaluatorSet.new(field_name)
              field_dsl = FieldEvaluatorDSL.new(field_set)
              begin
                field_dsl.instance_eval(&block)
              rescue StandardError => e
                # Log error for debugging instead of silently skipping
                if defined?(RAAF.logger)
                  RAAF.logger.warn "[EvaluatorDefinition] Failed to extract checks for field '#{field_name}': #{e.message}"
                  RAAF.logger.debug "[EvaluatorDefinition] Backtrace: #{e.backtrace&.first(5)&.join("\n")}"
                elsif defined?(Rails.logger)
                  Rails.logger.warn "[EvaluatorDefinition] Failed to extract checks for field '#{field_name}': #{e.message}"
                end
                next
              end

              # Extract each evaluator from the field set
              field_set.evaluators.each do |eval_config|
                evaluator_name = eval_config[:name]
                check_type = determine_check_type(evaluator_name)
                checks << {
                  field_name: field_name,
                  evaluator_type: evaluator_name,
                  check_type: check_type,
                  options: eval_config[:options],
                  display_name: eval_config[:display_name],
                  description: eval_config[:description]
                }
              end
            end
            checks
          end

          private

          # Determine the check type category from the evaluator name
          # @param evaluator_name [Symbol] The specific evaluator name
          # @return [Symbol] The check type category (:llm_judge, :statistical, :rule_based)
          def determine_check_type(evaluator_name)
            case evaluator_name.to_s
            when 'llm_judge', 'semantic_similarity'
              :llm_judge
            when 'consistency', 'no_regression', 'variance'
              :statistical
            else
              :rule_based
            end
          end

          public

          # Returns the field selections defined in the evaluator
          # @return [Array<Hash>] List of selections with :path and :as keys
          def field_selections
            @_evaluator_config[:selections]
          end

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

          # Register a result format callback that returns markdown for UI display
          # The block receives the field_result and span_data, and should return
          # a markdown string describing the evaluation results.
          #
          # @yield [field_result, span_data] Block that formats results as markdown
          # @yieldparam field_result [Hash] The evaluation result for a field
          # @yieldparam span_data [Hash] The original span data being evaluated
          # @yieldreturn [String] Markdown-formatted result description
          # @example
          #   result_format do |field_result, span_data|
          #     prospects = span_data[:prospect_evaluations] || []
          #     md = "## Evaluation Results\n\n"
          #     md << "**Status:** #{field_result[:status]}\n\n"
          #     md << "| Prospect | Score | Status |\n"
          #     md << "|----------|-------|--------|\n"
          #     prospects.each do |p|
          #       status = p[:score] >= 70 ? "Good" : p[:score] >= 40 ? "Average" : "Bad"
          #       md << "| #{p[:name]} | #{p[:score]} | #{status} |\n"
          #     end
          #     md
          #   end
          def result_format(&block)
            @_evaluator_config[:result_formatter] = block
          end

          # Returns the result formatter block if defined
          # @return [Proc, nil] The result formatter block or nil
          def result_formatter_block
            @_evaluator_config[:result_formatter]
          end

          # Register a span data transformer that converts span data before field extraction
          # This is useful when the agent output structure doesn't match the expected
          # field selection paths (e.g., array-based data that needs to be hash-based).
          #
          # @yield [span_data] Block that transforms the span data
          # @yieldparam span_data [Hash] The original span data
          # @yieldreturn [Hash] The transformed span data
          # @example Convert array-based criterion_scores to hash-based
          #   transform_span_data do |span_data|
          #     evaluations = span_data[:prospect_evaluations] || []
          #     transformed = evaluations.map do |eval|
          #       criterion_array = eval[:criterion_scores] || []
          #       criterion_hash = criterion_array.each_with_object({}) do |cs, h|
          #         h[cs[:criterion_code].to_sym] = cs.except(:criterion_code)
          #       end
          #       eval.merge(criterion_scores: criterion_hash)
          #     end
          #     span_data.merge(prospect_evaluations: transformed)
          #   end
          def transform_span_data(&block)
            RAAF.logger.info "[EvaluatorDefinition] transform_span_data called on #{name}"
            RAAF.logger.info "[EvaluatorDefinition] Setting span_transformer block: #{block.present?}"
            @_evaluator_config[:span_transformer] = block
            RAAF.logger.info "[EvaluatorDefinition] @_evaluator_config[:span_transformer] now set: #{@_evaluator_config[:span_transformer].present?}"
          end

          # Returns the span transformer block if defined
          # @return [Proc, nil] The span transformer block or nil
          def span_transformer_block
            @_evaluator_config[:span_transformer]
          end

          # Returns the per-field result formatter for a specific field
          # This builds the field evaluator set to extract its formatter.
          # @param field_name [Symbol] The field name to get formatter for
          # @return [Proc, nil] The field's result formatter or nil
          # @example
          #   formatter = MyEvaluator.field_result_formatter_for(:individual_scores)
          #   if formatter
          #     markdown = formatter.call(field_result, span_data)
          #   end
          def field_result_formatter_for(field_name)
            block = @_evaluator_config[:field_evaluations][field_name.to_sym]
            return nil unless block

            # Build a temporary field set to extract formatter
            field_set = FieldEvaluatorSet.new(field_name)
            field_dsl = FieldEvaluatorDSL.new(field_set)
            begin
              field_dsl.instance_eval(&block)
            rescue StandardError
              return nil
            end

            field_set.result_formatter
          end

          # @deprecated The `history` DSL method has been removed.
          #   Evaluation configuration is now managed via database-backed EvaluationPolicy.
          #   See docs/CONTINUOUS_EVAL_MIGRATION.md for migration instructions.
          #
          # @raise [RAAF::Eval::DeprecatedDSLError] Always raises when called
          # @example Migration
          #   # OLD (removed):
          #   history baseline: true, last_n: 10, auto_save: true
          #
          #   # NEW: Use EvaluationPolicy in database
          #   RAAF::Eval::Models::Continuous::EvaluationPolicy.create!(
          #     name: "my_policy",
          #     enabled: true,
          #     evaluators: [{ name: "my_evaluator" }]
          #   )
          def history(**_options)
            raise RAAF::Eval::DeprecatedDSLError.new("history")
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
          # Applies span_transformer if defined before evaluation
          # @param span_data [Hash] Span data to evaluate
          # @param options [Hash] Additional options passed to evaluator
          # @return [RAAF::Eval::Result] Evaluation result
          def evaluate(span_data, **options)
            # Debug logging to trace transformation
            RAAF.logger.info "=" * 60
            RAAF.logger.info "[EvaluatorDefinition] CLASS METHOD evaluate called!"
            RAAF.logger.info "[EvaluatorDefinition] Self: #{self.inspect}"
            RAAF.logger.info "[EvaluatorDefinition] Self.name: #{name}"
            RAAF.logger.info "[EvaluatorDefinition] @_evaluator_config present: #{@_evaluator_config.present?}"
            RAAF.logger.info "[EvaluatorDefinition] @_evaluator_config object_id: #{@_evaluator_config&.object_id}"
            RAAF.logger.info "[EvaluatorDefinition] span_transformer present: #{@_evaluator_config&.dig(:span_transformer).present?}"
            RAAF.logger.info "[EvaluatorDefinition] span_transformer object: #{@_evaluator_config&.dig(:span_transformer).inspect[0..100]}"
            RAAF.logger.info "=" * 60

            # Apply span transformer if defined
            transformed_data = if @_evaluator_config&.dig(:span_transformer)
              RAAF.logger.info "[EvaluatorDefinition] Applying span transformer"
              result = @_evaluator_config[:span_transformer].call(span_data)
              RAAF.logger.info "[EvaluatorDefinition] Transformation complete"
              result
            else
              RAAF.logger.info "[EvaluatorDefinition] No span transformer, using original data"
              span_data
            end

            evaluator.evaluate(transformed_data, **options)
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

              # Note: history configuration is no longer supported via DSL
              # Use database-backed EvaluationPolicy instead
            end
          end

          # Derives agent name from class name by removing Eval:: prefix
          # @return [String, nil] The derived agent name
          def derive_agent_name_from_class
            return nil unless name

            # Remove Eval:: prefix if present
            agent = name.sub(/^Eval::/, "")
            # Return nil if nothing changed (not in Eval namespace)
            agent == name ? nil : agent
          end
        end
      end
    end
  end
end
