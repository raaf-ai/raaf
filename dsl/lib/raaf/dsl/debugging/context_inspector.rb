# frozen_string_literal: true

module RAAF
  module DSL
    module Debugging
      # Provides debugging capabilities for inspecting context variables
      #
      # This class helps developers debug agent execution by displaying
      # formatted context variables and generating summaries of the current
      # agent state. It's particularly useful for understanding data flow
      # between agents in multi-agent workflows.
      #
      # @example Basic usage
      #   inspector = ContextInspector.new
      #   inspector.inspect_context(agent_instance)
      #
      # @example With custom logger
      #   inspector = ContextInspector.new(logger: my_logger)
      #   summary = inspector.context_summary(agent_instance)
      #   puts summary[:workflow_step]
      #
      # @example In agent execution
      #   class MyAgent < RAAF::DSL::Agents::Base
      #     def run
      #       inspector = ContextInspector.new
      #       inspector.inspect_context(self) if debug_enabled
      #       # ... agent logic ...
      #     end
      #   end
      #
      # @since 0.1.0
      class ContextInspector
        # @return [Logger] The logger instance used for output
        attr_reader :logger

        # Initialize a new context inspector
        #
        # @param logger [Logger] Logger instance for output (defaults to Rails.logger)
        # @example
        #   inspector = ContextInspector.new(logger: Rails.logger)
        def initialize(logger: nil)
          @logger = logger || ::Logger.new($stdout)
        end

        # Display formatted context variables for debugging
        #
        # Inspects the agent instance and outputs formatted context information
        # to the logger. Only runs if the agent has debug enabled.
        #
        # @param agent_instance [Object] The agent instance to inspect
        # @return [void]
        # @example
        #   inspector.inspect_context(my_agent)
        def inspect_context(agent_instance)
          return unless agent_instance.respond_to?(:debug_enabled) && agent_instance.debug_enabled

          logger.info "   🔍 CONTEXT INSPECTION:"
          logger.info "   #{'=' * 80}"

          display_context_variables(agent_instance)
          display_context_summary(agent_instance)

          logger.info "   #{'=' * 80}"
        end

        # Generate a summary of the current context state
        #
        # Creates a structured summary of key context variables, providing
        # a high-level overview of the agent's current state including
        # discovered entities, workflow progress, and other metrics.
        #
        # @param agent_instance [Object] The agent instance to summarize
        # @return [Hash] Summary hash with keys like :product, :workflow_step, etc.
        # @example
        #   summary = inspector.context_summary(agent)
        #   # => { product: "MyProduct", companies_discovered: 5, workflow_step: "enrichment" }
        def context_summary(agent_instance)
          return {} unless agent_instance.respond_to?(:context_variables)

          context_hash = agent_instance.context_variables.to_h
          {
            product: context_hash.dig(:product, :name) || "Unknown Product",
            search_strategies: context_hash[:search_strategies]&.length || 0,
            companies_discovered: context_hash[:discovered_companies]&.length || 0,
            companies_enriched: context_hash[:enriched_companies]&.length || 0,
            scored_prospects: context_hash[:scored_prospects]&.length || 0,
            workflow_step: determine_current_step(context_hash)
          }
        end

        private

        def display_context_variables(agent_instance)
          return unless agent_instance.respond_to?(:context_variables)

          logger.info "   🔍 FULL CONTEXT (using inspect):"

          # Use safe inspect with JSON formatting
          begin
            require "json"
            # Convert to JSON and back to ensure serializable, then pretty print
            context_hash = agent_instance.context_variables.to_h
            context_json = JSON.pretty_generate(JSON.parse(context_hash.to_json))
            context_lines = context_json.split("\n")

            context_lines.each do |line|
              logger.info "   │ #{line}"
            end
          rescue StandardError => e
            # Fallback to simple inspect if JSON fails
            logger.info "   │ #{agent_instance.context_variables.to_h.inspect}"
            logger.debug "   ⚠️ JSON formatting failed: #{e.message}"
          end
        end

        def display_context_summary(agent_instance)
          summary = context_summary(agent_instance)

          logger.info "   📊 CONTEXT SUMMARY:"
          summary.each do |key, value|
            logger.info "   │ #{key}: #{value}"
          end
        end

        def determine_current_step(context_hash)
          # Start with search strategy generation
          return "search_strategy" if context_hash[:search_strategies].blank?
          return "company_discovery" if context_hash[:discovered_companies].blank?
          return "company_enrichment" if context_hash[:enriched_companies].blank?
          return "prospect_scoring" if context_hash[:scored_prospects].blank?
          return "results_compilation" if context_hash[:final_results].blank?

          "completed"
        end
      end
    end
  end
end
