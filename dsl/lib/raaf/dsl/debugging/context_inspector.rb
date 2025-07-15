# frozen_string_literal: true

# ContextInspector provides debugging capabilities for context inspection
# by displaying formatted context variables and summaries
class AiAgentDsl::Debugging::ContextInspector
  attr_reader :logger

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  # Display formatted context variables for debugging
  def inspect_context(agent_instance)
    return unless agent_instance.respond_to?(:debug_enabled) && agent_instance.debug_enabled

    logger.info "   🔍 CONTEXT INSPECTION:"
    logger.info "   #{'=' * 80}"

    display_context_variables(agent_instance)
    display_context_summary(agent_instance)

    logger.info "   #{'=' * 80}"
  end

  # Generate a summary of the current context state
  def context_summary(agent_instance)
    return {} unless agent_instance.respond_to?(:context_variables)

    context_hash = agent_instance.context_variables.to_h
    {
      product:              context_hash.dig(:product, :name) || "Unknown Product",
      search_strategies:    context_hash[:search_strategies]&.length || 0,
      companies_discovered: context_hash[:discovered_companies]&.length || 0,
      companies_enriched:   context_hash[:enriched_companies]&.length || 0,
      scored_prospects:     context_hash[:scored_prospects]&.length || 0,
      workflow_step:        determine_current_step(context_hash)
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
