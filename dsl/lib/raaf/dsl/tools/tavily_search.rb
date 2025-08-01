# frozen_string_literal: true

# Tavily Search Tool for AI Agent DSL
#
# Provides reliable web search functionality using Tavily's API,
# designed specifically for AI applications with clean, structured results.
#
# @example Basic usage in an agent
#   class MyAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::AgentDsl
#
#     uses_tool :tavily_search
#   end
#
# @example With custom configuration
#   class MyAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::AgentDsl
#
#     uses_tool :tavily_search,
#       search_depth: "advanced",
#       max_results: 10,
#       include_domains: ["github.com", "stackoverflow.com"]
#   end
#
module RAAF
  module DSL
    module Tools
      class TavilySearch < Base
        # Valid search depth options
        VALID_SEARCH_DEPTHS = %w[basic advanced].freeze

        # Default configuration
        DEFAULT_CONFIG = {
          search_depth: "basic",
          max_results: 5,
          include_answer: false,
          include_raw_content: false,
          exclude_domains: [],
          include_domains: [],
          timeout: 30
        }.freeze

        def initialize(options = {})
          super(DEFAULT_CONFIG.merge(options || {}))
          validate_options!
        end

        # Returns the standardized tool name for Tavily search functionality
        #
        # @return [String] The tool name "tavily_search"
        def tool_name
          "tavily_search"
        end

        # Returns the tool name (required by agent system)
        # This is an alias for tool_name for compatibility
        #
        # @return [String] The tool name "tavily_search"
        def name
          tool_name
        end

        # Returns the tool description for agent system
        #
        # @return [String] Description of what this tool does
        def description
          "Search the web for current information using Tavily API. Returns structured results with titles, URLs, content summaries, and relevance scores."
        end

        # Main execution method expected by agent system
        # Delegates to the search method with the provided parameters
        #
        # @param params [Hash] Search parameters
        # @return [Hash] Search results
        def call(**params)
          search(**params)
        end

        protected

        def build_tool_definition
          {
            type: "tavily_search",
            description: "Search the web for current information using Tavily API. Returns structured results with titles, URLs, content summaries, and relevance scores.",
            parameters: {
              type: "object",
              properties: {
                query: {
                  type: "string",
                  description: "The search query. Supports site: operators (e.g., 'site:github.com Ruby AI tools')"
                },
                search_depth: {
                  type: "string",
                  enum: VALID_SEARCH_DEPTHS,
                  description: "Search depth - 'basic' for quick results, 'advanced' for comprehensive search"
                },
                max_results: {
                  type: "integer",
                  minimum: 1,
                  maximum: 20,
                  description: "Maximum number of results to return"
                },
                include_domains: {
                  type: "array",
                  items: { type: "string" },
                  description: "Only include results from these domains"
                },
                exclude_domains: {
                  type: "array",
                  items: { type: "string" },
                  description: "Exclude results from these domains"
                }
              },
              required: ["query"],
              additionalProperties: false
            }
          }
        end

        private

        def validate_options!
          if options[:search_depth] && !VALID_SEARCH_DEPTHS.include?(options[:search_depth])
            raise ArgumentError,
                  "Invalid search_depth: #{options[:search_depth]}. Must be one of: #{VALID_SEARCH_DEPTHS.join(', ')}"
          end

          return unless options[:max_results] && (options[:max_results] < 1 || options[:max_results] > 20)

          raise ArgumentError, "Invalid max_results: #{options[:max_results]}. Must be between 1 and 20"
        end

        # Application metadata for enhanced tool definition
        def application_metadata
          metadata = {}

          metadata[:search_depth] = options[:search_depth]
          metadata[:max_results] = options[:max_results]

          metadata[:include_domains] = options[:include_domains] if options[:include_domains].any?

          metadata[:exclude_domains] = options[:exclude_domains] if options[:exclude_domains].any?

          metadata
        end
      end
    end
  end
end
