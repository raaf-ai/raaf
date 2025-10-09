# frozen_string_literal: true

require "raaf-core"
require "raaf/perplexity/common"
require "raaf/perplexity/search_options"
require "raaf/perplexity/result_parser"

module RAAF
  module Tools
    ##
    # Perplexity web search tool for RAAF agents
    #
    # Provides web-grounded search capabilities with automatic citations using Perplexity AI.
    # Supports all Perplexity models, domain/recency filtering, and structured output.
    #
    # This tool is designed to be wrapped by RAAF::FunctionTool for use with agents.
    # It provides a simple callable interface that returns formatted search results.
    #
    # @example Basic search
    #   tool = PerplexityTool.new(api_key: ENV["PERPLEXITY_API_KEY"])
    #   result = tool.call(query: "Latest Ruby news", model: "sonar")
    #
    # @example Search with filters
    #   result = tool.call(
    #     query: "Ruby security updates",
    #     model: "sonar-pro",
    #     search_domain_filter: ["ruby-lang.org"],
    #     search_recency_filter: "week"
    #   )
    #
    # @example Use with RAAF agent
    #   agent = RAAF::Agent.new(name: "Research Agent", model: "gpt-4o")
    #   tool_instance = PerplexityTool.new(api_key: ENV["PERPLEXITY_API_KEY"])
    #   function_tool = RAAF::FunctionTool.new(
    #     tool_instance.method(:call),
    #     name: "perplexity_search",
    #     description: "Perform web-grounded search with citations"
    #   )
    #   agent.add_tool(function_tool)
    #
    class PerplexityTool
      ##
      # Initialize Perplexity tool with API credentials
      #
      # @param api_key [String, nil] Perplexity API key (defaults to PERPLEXITY_API_KEY env var)
      # @param api_base [String, nil] Custom API base URL
      # @param timeout [Integer, nil] Request timeout in seconds
      # @param open_timeout [Integer, nil] Connection timeout in seconds
      #
      def initialize(api_key: nil, api_base: nil, timeout: nil, open_timeout: nil)
        @provider = RAAF::Models::PerplexityProvider.new(
          api_key: api_key,
          api_base: api_base,
          timeout: timeout,
          open_timeout: open_timeout
        )
      end

      ##
      # Execute Perplexity search with the given parameters
      #
      # Performs web-grounded search using Perplexity AI with automatic citations.
      # Best for research tasks requiring current information with source attribution.
      #
      # Use this tool when you need:
      # - Recent, factual information from the web
      # - Cited sources and references
      # - Domain-specific research
      # - Time-sensitive queries
      #
      # @param query [String] Search query for web research (required)
      # @param model [String] Perplexity model: sonar (fast), sonar-pro (advanced+schema),
      #   sonar-reasoning (deep), sonar-reasoning-pro (premium+schema).
      #   Default: "sonar". Valid values: #{RAAF::Perplexity::Common::SUPPORTED_MODELS.join(', ')}
      # @param search_domain_filter [Array<String>, nil] Array of domain names to restrict search
      #   (e.g., ['ruby-lang.org', 'github.com'])
      # @param search_recency_filter [String, nil] Time window for results.
      #   Valid values: hour, day, week, month, year
      # @param max_tokens [Integer, nil] Maximum tokens in response (1-4000)
      # @return [Hash] Formatted search result with success, content, citations, web_results
      #
      def call(query:, model: "sonar", search_domain_filter: nil, search_recency_filter: nil, max_tokens: nil)
        # Build messages for Perplexity
        messages = [{ role: "user", content: query }]

        # Build request parameters
        kwargs = {}
        kwargs[:max_tokens] = max_tokens if max_tokens

        # Add web search options using common code
        if search_domain_filter || search_recency_filter
          options = RAAF::Perplexity::SearchOptions.build(
            domain_filter: search_domain_filter,
            recency_filter: search_recency_filter
          )
          kwargs[:web_search_options] = options if options
        end

        # Execute search using provider
        result = @provider.chat_completion(
          messages: messages,
          model: model,
          **kwargs
        )

        # Format result using common parser
        RAAF::Perplexity::ResultParser.format_search_result(result)
      rescue RAAF::AuthenticationError => e
        {
          success: false,
          error: "Authentication failed",
          error_type: "authentication_error",
          message: e.message
        }
      rescue RAAF::RateLimitError => e
        {
          success: false,
          error: "Rate limit exceeded",
          error_type: "rate_limit_error",
          message: e.message
        }
      rescue StandardError => e
        {
          success: false,
          error: "Search failed",
          error_type: "general_error",
          message: e.message,
          backtrace: e.backtrace.first(5)
        }
      end
    end
  end
end
