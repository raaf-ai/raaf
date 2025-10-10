# frozen_string_literal: true

require "raaf/perplexity/http_client"
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
      # @param model [String] Default Perplexity model to use (default: "sonar")
      # @param max_tokens [Integer, nil] Default maximum tokens in response (default: nil)
      # @param search_recency_filter [String, nil] Default recency filter fallback (default: nil = no recency filtering)
      # @param timeout [Integer, nil] Request timeout in seconds
      # @param open_timeout [Integer, nil] Connection timeout in seconds
      #
      def initialize(api_key: nil, api_base: nil, model: "sonar", max_tokens: nil, search_recency_filter: nil, timeout: nil, open_timeout: nil)
        @model = model
        @max_tokens = max_tokens
        @default_search_recency_filter = search_recency_filter
        @http_client = RAAF::Perplexity::HttpClient.new(
          api_key: api_key || ENV.fetch("PERPLEXITY_API_KEY", nil),
          api_base: api_base,
          timeout: timeout,
          open_timeout: open_timeout
        )
      end

      ##
      # Generate complete FunctionTool parameter schema for Perplexity search
      #
      # This provides the complete OpenAI function schema including parameters,
      # types, enums, and defaults. The LLM sees exactly what parameters are
      # available and their valid values.
      #
      # @return [Hash] Complete parameter schema for FunctionTool
      #
      # @example Using with FunctionTool
      #   perplexity_tool = RAAF::Tools::PerplexityTool.new(api_key: ENV['PERPLEXITY_API_KEY'])
      #   function_tool = RAAF::FunctionTool.new(
      #     perplexity_tool.method(:call),
      #     name: "perplexity_search",
      #     description: RAAF::Tools::PerplexityTool.function_tool_description,
      #     parameters: RAAF::Tools::PerplexityTool.function_tool_parameters
      #   )
      #   agent.add_tool(function_tool)
      #
      def self.function_tool_parameters
        {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search query for web research. Use expert terminology and combine multiple facts into one comprehensive query. " \
                          "Example: '[Company] [Legal Form] [City] [Country] comprehensive business profile: business model, industry sector, B2B/B2C focus, company size, activity status'"
            },
            search_domain_filter: {
              type: "array",
              items: { type: "string" },
              description: "Optional: Array of complete domain names to restrict search to authoritative sources. " \
                          "CRITICAL: Must be complete domain names with subdomain/domain + TLD (e.g., 'example.com'). " \
                          "✅ Valid: ['example.com', 'ruby-lang.org', 'subdomain.example.com', 'news.bbc.co.uk'] " \
                          "❌ Invalid: ['nl' (TLD only), '.nl' (TLD filter), '*.nl' (wildcards), '*.com', 'ruby-*'] " \
                          "TLD-only patterns are not supported - use complete domain names only."
            },
            search_recency_filter: {
              type: "string",
              enum: ["hour", "day", "week", "month", "year"],
              description: "Optional: Time window for search results. Use for time-sensitive queries requiring recent information."
            }
          },
          required: ["query"]
        }
      end

      ##
      # Generate comprehensive FunctionTool description for Perplexity search
      #
      # This provides the LLM with complete context about when and how to use
      # the Perplexity search tool effectively, based on production usage patterns.
      #
      # @return [String] Complete tool description for FunctionTool wrapper
      #
      # @example Using with FunctionTool
      #   perplexity_tool = RAAF::Tools::PerplexityTool.new(api_key: ENV['PERPLEXITY_API_KEY'])
      #   function_tool = RAAF::FunctionTool.new(
      #     perplexity_tool.method(:call),
      #     name: "perplexity_search",
      #     description: RAAF::Tools::PerplexityTool.function_tool_description,
      #     parameters: RAAF::Tools::PerplexityTool.function_tool_parameters
      #   )
      #   agent.add_tool(function_tool)
      #
      def self.function_tool_description
        <<~DESC.strip
          Search the web for current, factual information with automatic citations using Perplexity AI.

          **Model Configuration:**
          - The search model and max_tokens are configured at tool initialization time
          - You cannot change the model per query - use the model configured when the tool was created

          **When to Use This Tool:**
          - You need recent, factual information from the web (news, announcements, updates)
          - You need cited sources and references for verification
          - You need domain-specific research from authoritative sources
          - You need time-sensitive queries where accuracy is critical
          - You lack complete data and need to fill information gaps (e.g., data_completeness_score < 7)

          **When NOT to Use:**
          - You already have complete, high-quality data available (avoid redundant API calls)
          - Query is about general knowledge covered in your training
          - Task requires reasoning/analysis rather than fact-gathering

          **Query Engineering Best Practices:**

          1. **Use Expert Terminology** - Professional language, not conversational
             ✅ Good: "SaaS company Netherlands B2B revenue model employee count"
             ❌ Bad: "Tell me about this company and what they do"

          2. **Combine Facts in ONE Search** - Comprehensive queries are more efficient
             ✅ Good: "[Company] [Legal Form] [City] [Country] comprehensive business profile: business model, industry sector, B2B/B2C focus, company size, activity status"
             ❌ Bad: Multiple separate searches for each fact

          3. **Be Specific** - Add 2-3 contextual words for precision
             ✅ Good: "Ruby 3.4 performance improvements JIT compiler"
             ❌ Bad: "Ruby performance"

          4. **Use Filters for Focus:**
             - search_domain_filter: Complete domain names only (no TLD-only patterns)
               ✅ Valid: ["ruby-lang.org", "github.com", "news.bbc.co.uk", "example.com"]
               ❌ Invalid: ["nl", ".nl" (TLD filters), "*.nl" (wildcards), "*.com", "ruby-*"]
               Use complete domain names with subdomain/domain + TLD
             - search_recency_filter: Time window ("week", "month") for current information

          **Response Structure:**

          Successful searches return:
          - content: Main search result text with citations
          - citations: Array of source URLs
          - web_results: Detailed results with title, URL, snippet
          - model: Model used for the search

          **Always include citations in your final response** to maintain factual accuracy and transparency.
        DESC
      end

      ##
      # Execute Perplexity search with the given parameters
      #
      # Performs web-grounded search using Perplexity AI with automatic citations.
      # Best for research tasks requiring current information with source attribution.
      #
      # **QUERY ENGINEERING BEST PRACTICES:**
      # - Use expert terminology, NOT conversational language
      # - Combine multiple facts into ONE comprehensive query (not multiple searches)
      # - Pattern: "[Entity] [Type] [Location] comprehensive profile: [specific facts needed]"
      # - Be specific with 2-3 contextual words for better results
      #
      # **EFFICIENCY GUIDELINES:**
      # - Prefer single comprehensive search over multiple narrow searches
      # - Use search_domain_filter to focus on authoritative sources
      # - Use search_recency_filter for time-sensitive queries
      # - Check data completeness before searching (avoid redundant API calls)
      #
      # **Use this tool when you need:**
      # - Recent, factual information from the web
      # - Cited sources and references
      # - Domain-specific research from authoritative sources
      # - Time-sensitive queries where accuracy is critical
      # - To fill information gaps when data_completeness_score < 7
      #
      # **When NOT to use:**
      # - You already have complete, high-quality data available
      # - Query is about general knowledge covered in training data
      # - Task requires reasoning/analysis rather than fact-gathering
      #
      # @param query [String] Search query for web research (required).
      #   Example: "Acme Corp BV Amsterdam Netherlands comprehensive business profile: business model, industry sector, B2B/B2C focus, company size, activity status"
      # @param search_domain_filter [Array<String>, nil] Array of complete domain names to restrict search.
      #   Valid: ['example.com', 'ruby-lang.org', 'subdomain.example.com', 'news.bbc.co.uk']
      #   Invalid: ['nl' (TLD only), '.nl' (TLD filter), '*.nl' (wildcards), '*.com', 'ruby-*']
      #   TLD-only patterns are not supported - use complete domain names only.
      # @param search_recency_filter [String, nil] Time window for results.
      #   Valid values: hour, day, week, month, year
      # @return [Hash] Formatted search result with success, content, citations, web_results
      #
      def call(query:, search_domain_filter: nil, search_recency_filter: nil)
        # Validate all input parameters
        validate_query(query)
        validate_domain_filter(search_domain_filter) if search_domain_filter
        # recency_filter validation is handled by SearchOptions.build with fallback

        # Build messages for Perplexity
        messages = [{ role: "user", content: query }]

        # Build request body for Perplexity API
        body = {
          model: @model,
          messages: messages
        }

        # Add max_tokens if specified
        body[:max_tokens] = @max_tokens if @max_tokens

        # Add web search options using common code with validation fallback
        if search_domain_filter || search_recency_filter
          # Try to build options with agent-provided recency_filter
          begin
            options = RAAF::Perplexity::SearchOptions.build(
              domain_filter: search_domain_filter,
              recency_filter: search_recency_filter
            )
            body.merge!(options) if options
          rescue ArgumentError => e
            # Agent provided invalid recency_filter - fall back to default
            if e.message.include?("Invalid recency filter")
              RAAF.logger.warn "⚠️  [PerplexityTool] Invalid recency_filter '#{search_recency_filter}' - falling back to default: #{@default_search_recency_filter.inspect}"

              # Retry with default recency_filter
              options = RAAF::Perplexity::SearchOptions.build(
                domain_filter: search_domain_filter,
                recency_filter: @default_search_recency_filter
              )
              body.merge!(options) if options
            else
              # Re-raise if it's a different ArgumentError (e.g., invalid domain_filter)
              raise
            end
          end
        end

        # Execute search using HttpClient directly
        result = @http_client.make_api_call(body)

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

      private

      ##
      # Validates the query parameter
      #
      # @param query [String] Search query to validate
      # @raise [ArgumentError] if query is invalid
      # @return [void]
      #
      def validate_query(query)
        raise ArgumentError, "Query parameter is required" if query.nil?
        raise ArgumentError, "Query must be a String, got #{query.class}" unless query.is_a?(String)
        raise ArgumentError, "Query cannot be empty" if query.strip.empty?
        raise ArgumentError, "Query is too long (maximum 4000 characters)" if query.length > 4000
      end

      ##
      # Validates the domain_filter parameter
      #
      # @param domain_filter [Array<String>, String] Domain filter to validate
      # @raise [ArgumentError] if domain_filter is invalid
      # @return [void]
      #
      def validate_domain_filter(domain_filter)
        # Check type first
        unless domain_filter.is_a?(String) || domain_filter.is_a?(Array)
          raise ArgumentError, "search_domain_filter must be a String or Array, got #{domain_filter.class}"
        end

        # Convert to array for uniform validation
        domains = Array(domain_filter)

        # Check each domain for invalid patterns
        domains.each do |domain|
          next unless domain.is_a?(String)

          # Check for wildcard characters
          if domain.include?("*") || domain.include?("?")
            raise ArgumentError,
                  "Invalid domain pattern '#{domain}': Wildcard patterns (*, ?) are not supported. " \
                  "Use exact domain names like 'example.com' or 'subdomain.example.com'. " \
                  "Valid examples: ['ruby-lang.org', 'github.com', 'news.bbc.co.uk']. " \
                  "Invalid examples: ['*.nl', '*.com', 'ruby-*', '*github*']"
          end

          # Check for TLD-only patterns (with or without leading dot)
          # Only allow complete domain names with at least one subdomain/domain part
          if !domain.include?(".") || domain.start_with?(".") || domain.count(".") < 1 || domain.split(".").any?(&:empty?)
            raise ArgumentError,
                  "Invalid domain pattern '#{domain}': TLD-only patterns are not supported. " \
                  "Use complete domain names like 'example.nl', 'ruby-lang.org', or 'news.bbc.co.uk'. " \
                  "TLD filters like '.nl', 'nl', '.com' are not allowed."
          end
        end
      end
    end
  end
end
