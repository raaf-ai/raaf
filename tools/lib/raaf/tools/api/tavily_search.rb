# frozen_string_literal: true

require "raaf-dsl"

module RAAF
  module Tools
    module API
      # Tavily Search Tool - Clean implementation using new DSL
      #
      # Provides advanced web search using Tavily's API with minimal boilerplate.
      # Supports search depth control, domain filtering, and AI-generated summaries.
      #
      # @example Basic usage
      #   tool = RAAF::Tools::API::TavilySearch.new
      #   result = tool.call(query: "latest AI news")
      #
      # @example Advanced search with options
      #   result = tool.call(
      #     query: "Ruby AI frameworks",
      #     search_depth: "advanced",
      #     max_results: 10,
      #     include_answer: true
      #   )
      #
      class TavilySearch < RAAF::DSL::Tools::Tool::API
        endpoint "https://api.tavily.com/search"
        api_key ENV["TAVILY_API_KEY"]
        timeout 30

        # Execute Tavily search
        #
        # @param query [String] Search query
        # @param search_depth [String] "basic" or "advanced"
        # @param max_results [Integer] Number of results (1-20)
        # @param include_answer [Boolean] Include AI-generated summary
        # @param include_domains [Array<String>] Domains to include
        # @param exclude_domains [Array<String>] Domains to exclude
        # @return [Hash] Search results
        #
        def call(query:, search_depth: "basic", max_results: 5, include_answer: false, 
                 include_domains: [], exclude_domains: [])
          
          params = {
            api_key: api_key,
            query: query,
            search_depth: search_depth,
            max_results: max_results,
            include_answer: include_answer,
            include_raw_content: false
          }

          # Add domain filters if provided
          params[:include_domains] = include_domains if include_domains.any?
          params[:exclude_domains] = exclude_domains if exclude_domains.any?

          response = post(json: params)
          
          # Return structured results
          if response[:error]
            {
              success: false,
              error: response[:error],
              query: query,
              results: []
            }
          else
            {
              success: true,
              query: query,
              results_count: (response["results"] || []).length,
              results: response["results"] || [],
              answer: response["answer"],
              follow_up_questions: response["follow_up_questions"] || []
            }
          end
        end

        # Tool configuration for agents
        def to_tool_definition
          {
            type: "function",
            function: {
              name: "tavily_search",
              description: "Search the web using Tavily API for finding current information",
              parameters: {
                type: "object",
                properties: {
                  query: {
                    type: "string",
                    description: "The search query"
                  },
                  search_depth: {
                    type: "string",
                    enum: ["basic", "advanced"],
                    description: "Search depth: 'basic' or 'advanced'"
                  },
                  max_results: {
                    type: "integer",
                    minimum: 1,
                    maximum: 20,
                    description: "Maximum number of results (1-20)"
                  },
                  include_answer: {
                    type: "boolean",
                    description: "Include AI-generated summary of results"
                  },
                  include_domains: {
                    type: "array",
                    items: { type: "string" },
                    description: "Domains to include in search"
                  },
                  exclude_domains: {
                    type: "array", 
                    items: { type: "string" },
                    description: "Domains to exclude from search"
                  }
                },
                required: ["query"]
              }
            }
          }
        end

        # Tool name for agent registration
        def name
          "tavily_search"
        end

        # Check if tool is enabled
        def enabled?
          !api_key.nil? && !api_key.empty?
        end
      end
    end
  end
end