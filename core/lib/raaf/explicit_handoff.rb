# frozen_string_literal: true

require_relative "handoff_context"
require_relative "handoff_tool"

module RAAF
  ##
  # Explicit handoff system that replaces hook-based handoffs
  #
  # This module provides the new explicit handoff system that uses
  # direct function calling instead of conversation parsing and hooks.
  #
  module ExplicitHandoff
    ##
    # Add explicit handoff tools to an agent
    #
    # @param agent [Agent] The agent to add handoff tools to
    # @param handoff_context [HandoffContext] Context for managing handoffs
    # @param handoff_configs [Array<Hash>] Array of handoff configurations
    #
    # @example Add handoff tools to an agent
    #   context = RAAF::HandoffContext.new
    #   handoff_configs = [
    #     {
    #       target_agent: "CompanyDiscoveryAgent",
    #       data_contract: RAAF::HandoffTool.search_strategies_contract
    #     }
    #   ]
    #   RAAF::ExplicitHandoff.add_handoff_tools(agent, context, handoff_configs)
    #
    def self.add_handoff_tools(agent, handoff_context, handoff_configs)
      handoff_configs.each do |config|
        handoff_tool = HandoffTool.create_handoff_tool(
          target_agent: config[:target_agent],
          handoff_context: handoff_context,
          data_contract: config[:data_contract] || {}
        )
        agent.add_tool(handoff_tool)
      end
    end

    ##
    # Create a search agent with explicit handoff capability
    #
    # @param handoff_context [HandoffContext] Context for managing handoffs
    # @return [Agent] Configured search agent
    #
    def self.create_search_agent(handoff_context)
      agent = Agent.new(
        name: "SearchAgent",
        instructions: build_search_instructions,
        model: "gpt-4o"
      )

      # Add web search tool
      if defined?(RAAF::Tools::WebSearchTool)
        agent.add_tool(RAAF::Tools::WebSearchTool.new)
      end

      # Add handoff tool for company discovery
      handoff_tool = HandoffTool.create_handoff_tool(
        target_agent: "CompanyDiscoveryAgent",
        handoff_context: handoff_context,
        data_contract: HandoffTool.search_strategies_contract
      )
      agent.add_tool(handoff_tool)

      agent
    end

    ##
    # Create a company discovery agent with explicit completion capability
    #
    # @param handoff_context [HandoffContext] Context for managing handoffs
    # @return [Agent] Configured company discovery agent
    #
    def self.create_company_discovery_agent(handoff_context)
      agent = Agent.new(
        name: "CompanyDiscoveryAgent",
        instructions: build_company_discovery_instructions,
        model: "gpt-4o"
      )

      # Add web search tool
      if defined?(RAAF::Tools::WebSearchTool)
        agent.add_tool(RAAF::Tools::WebSearchTool.new)
      end

      # Add completion tool
      completion_tool = HandoffTool.create_completion_tool(
        handoff_context: handoff_context,
        data_contract: HandoffTool.company_discovery_contract
      )
      agent.add_tool(completion_tool)

      agent
    end

    ##
    # Run explicit handoff workflow
    #
    # @param message [String] Initial message
    # @return [WorkflowResult] Complete workflow result
    #
    def self.run_explicit_handoff_workflow(message)
      handoff_context = HandoffContext.new(current_agent: "SearchAgent")

      # Define agents
      agents = {
        "SearchAgent" => {
          name: "SearchAgent",
          class: Agent,
          instructions: build_search_instructions,
          model: "gpt-4o",
          tools: web_search_tools,
          handoff_tools: [
            {
              target_agent: "CompanyDiscoveryAgent",
              data_contract: HandoffTool.search_strategies_contract
            }
          ]
        },
        "CompanyDiscoveryAgent" => {
          name: "CompanyDiscoveryAgent",
          class: Agent,
          instructions: build_company_discovery_instructions,
          model: "gpt-4o",
          tools: web_search_tools,
          terminal: true,
          completion_contract: HandoffTool.company_discovery_contract
        }
      }

      # Create orchestrator
      orchestrator = AgentOrchestrator.new(agents: agents)

      # Run workflow
      orchestrator.run_workflow(message, starting_agent: "SearchAgent")
    end

    private

    ##
    # Build instructions for search agent
    #
    # @return [String] Search agent instructions
    #
    def self.build_search_instructions
      <<~INSTRUCTIONS.strip
        You are a SearchAgent specializing in market research and search strategy development.
        
        Your role is to:
        1. Analyze the user's request to understand their research needs
        2. Conduct initial market research using web search
        3. Develop comprehensive search strategies for company discovery
        4. Gather market insights and trends
        5. Transfer execution to CompanyDiscoveryAgent with your findings
        
        IMPORTANT: You must call the handoff_to_companydiscoveryagent function when you have:
        - Completed your market research
        - Developed search strategies
        - Gathered market insights
        
        The handoff function expects:
        - search_strategies: Array of strategy objects with name, queries, and priority
        - market_insights: Object with trends, key_players, market_size, growth_rate
        - reason: String explaining why you're handing off
        
        Be thorough in your research but efficient in your handoff.
      INSTRUCTIONS
    end

    ##
    # Build instructions for company discovery agent
    #
    # @return [String] Company discovery agent instructions
    #
    def self.build_company_discovery_instructions
      <<~INSTRUCTIONS.strip
        You are a CompanyDiscoveryAgent specializing in finding and analyzing companies.
        
        You will receive handoff data from SearchAgent containing:
        - Search strategies developed for company discovery
        - Market insights and trends
        - Context about the user's research needs
        
        Your role is to:
        1. Use the provided search strategies to find relevant companies
        2. Conduct detailed research on discovered companies
        3. Analyze and score companies based on relevance
        4. Compile comprehensive company profiles
        5. Complete the workflow with your findings
        
        IMPORTANT: You must call the complete_workflow function when you have:
        - Discovered and researched companies using the provided strategies
        - Analyzed company relevance and created profiles
        - Compiled your final results
        
        The completion function expects:
        - discovered_companies: Array of company objects with name, industry, website, etc.
        - search_metadata: Object with search statistics
        - workflow_status: "completed", "partial", or "failed"
        
        Be thorough and provide detailed company information.
      INSTRUCTIONS
    end

    ##
    # Get web search tools
    #
    # @return [Array] Array of web search tools
    #
    def self.web_search_tools
      tools = []
      if defined?(RAAF::Tools::WebSearchTool)
        tools << RAAF::Tools::WebSearchTool.new
      end
      tools
    end
  end
end