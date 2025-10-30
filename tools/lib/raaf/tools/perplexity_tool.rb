# frozen_string_literal: true

require "raaf/errors"
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
      # Initialize Perplexity tool with API credentials and optional parameters
      #
      # @param api_key [String, nil] Perplexity API key (defaults to PERPLEXITY_API_KEY env var)
      # @param api_base [String, nil] Custom API base URL
      # @param model [String] Default Perplexity model to use (default: "sonar")
      # @param api_type [String] API endpoint type: "chat" for /chat/completions or "search" for /search (default: "chat")
      # @param max_results [Integer, nil] Default maximum search results (default: nil, only for Search API)
      # @param max_tokens [Integer, nil] Default maximum tokens in response (default: nil)
      # @param temperature [Float, nil] Controls randomness (0-2, default: nil). 0 = deterministic
      # @param top_p [Float, nil] Nucleus sampling parameter (0-1, default: nil)
      # @param presence_penalty [Float, nil] Reduces repetition of tokens (default: nil)
      # @param frequency_penalty [Float, nil] Reduces frequency-based repetition (default: nil)
      # @param search_recency_filter [String, nil] Default recency filter fallback (default: nil = no recency filtering)
      # @param response_format [Hash, nil] Response format schema (for compatible models, default: nil)
      # @param reasoning_effort [String, nil] Reasoning level for reasoning models ('low', 'medium', 'high', default: nil)
      # @param language_preference [String, nil] Preferred response language (default: nil)
      # @param timeout [Integer, nil] Request timeout in seconds
      # @param open_timeout [Integer, nil] Connection timeout in seconds
      # @param include_search_results_in_content [Boolean] Include web_results in response content (default: false)
      #
      def initialize(api_key: nil, api_base: nil, model: "sonar", api_type: "chat", max_results: nil,
                     max_tokens: nil, temperature: nil, top_p: nil, presence_penalty: nil, frequency_penalty: nil,
                     search_recency_filter: nil, response_format: nil, reasoning_effort: nil,
                     language_preference: nil, timeout: nil, open_timeout: nil,
                     include_search_results_in_content: false)
        @model = model
        @api_type = api_type
        @max_results = max_results
        @max_tokens = max_tokens
        @temperature = temperature
        @top_p = top_p
        @presence_penalty = presence_penalty
        @frequency_penalty = frequency_penalty
        @response_format = response_format
        @reasoning_effort = reasoning_effort
        @language_preference = language_preference
        @default_search_recency_filter = search_recency_filter
        @include_search_results_in_content = include_search_results_in_content
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
            max_results: {
              type: "integer",
              minimum: 1,
              maximum: 20,
              description: "Optional: Maximum number of search results to return (1-20). Only applies when using Search API. Default depends on model."
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
            },
            temperature: {
              type: "number",
              minimum: 0,
              maximum: 2,
              description: "Optional: Controls randomness in response synthesis (0-2). Use 0 for deterministic/reproducible results. Default varies by model."
            },
            top_p: {
              type: "number",
              minimum: 0,
              maximum: 1,
              description: "Optional: Nucleus sampling parameter (0-1). Controls diversity of results. Lower = more focused."
            },
            presence_penalty: {
              type: "number",
              description: "Optional: Reduces repetition of tokens already present in the context. Range typically -2 to 2."
            },
            frequency_penalty: {
              type: "number",
              description: "Optional: Reduces frequency-based repetition. Range typically -2 to 2."
            },
            return_citations: {
              type: "boolean",
              description: "Optional: Include citations in response (Search API only). Default: true"
            },
            return_images: {
              type: "boolean",
              description: "Optional: Include images in response (Search API only). Default: false"
            },
            return_related_questions: {
              type: "boolean",
              description: "Optional: Include related questions in response (Search API only). Default: false"
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
          - The search model is configured at tool initialization time
          - You cannot change the model per query - use the model configured when the tool was created
          - Advanced parameters (temperature, top_p, reasoning_effort, etc.) can be configured at initialization or per-query

          **Parameter Control:**
          - **temperature** (0-2): Controls response synthesis randomness. Use 0 for deterministic/reproducible results
          - **top_p** (0-1): Nucleus sampling parameter. Lower values = more focused results
          - **presence_penalty** / **frequency_penalty**: Control token repetition in responses
          - All parameters can be set at tool initialization time (defaults for all queries) or per-query (overrides defaults)

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
      # @param max_results [Integer, nil] Maximum number of search results (1-20, Search API only). Overrides initialize default if provided.
      # @param search_domain_filter [Array<String>, nil] Array of complete domain names to restrict search.
      #   Valid: ['example.com', 'ruby-lang.org', 'subdomain.example.com', 'news.bbc.co.uk']
      #   Invalid: ['nl' (TLD only), '.nl' (TLD filter), '*.nl' (wildcards), '*.com', 'ruby-*']
      #   TLD-only patterns are not supported - use complete domain names only.
      # @param search_recency_filter [String, nil] Time window for results.
      #   Valid values: hour, day, week, month, year
      # @param temperature [Float, nil] Controls randomness (0-2). Overrides initialize default if provided.
      # @param top_p [Float, nil] Nucleus sampling (0-1). Overrides initialize default if provided.
      # @param presence_penalty [Float, nil] Token repetition penalty. Overrides initialize default if provided.
      # @param frequency_penalty [Float, nil] Frequency repetition penalty. Overrides initialize default if provided.
      # @param return_citations [Boolean, nil] Include citations in Search API response
      # @param return_images [Boolean, nil] Include images in Search API response
      # @param return_related_questions [Boolean, nil] Include related questions in Search API response
      # @return [Hash] Formatted search result with success, content, citations, web_results
      #
      def call(query:, max_results: nil, search_domain_filter: nil, search_recency_filter: nil,
               temperature: nil, top_p: nil, presence_penalty: nil, frequency_penalty: nil,
               return_citations: nil, return_images: nil, return_related_questions: nil)
        # Normalize empty strings to nil for both filters
        search_domain_filter = normalize_filter(search_domain_filter)
        search_recency_filter = normalize_filter(search_recency_filter)

        # Validate all input parameters
        validate_query(query)
        validate_domain_filter(search_domain_filter) if search_domain_filter
        # recency_filter validation is handled by SearchOptions.build with fallback

        # Route to appropriate API based on api_type
        if @api_type == "search"
          call_search_api(
            query: query,
            max_results: max_results,
            search_domain_filter: search_domain_filter,
            search_recency_filter: search_recency_filter,
            return_citations: return_citations,
            return_images: return_images,
            return_related_questions: return_related_questions
          )
        else
          call_chat_api(
            query: query,
            search_domain_filter: search_domain_filter,
            search_recency_filter: search_recency_filter,
            temperature: temperature,
            top_p: top_p,
            presence_penalty: presence_penalty,
            frequency_penalty: frequency_penalty
          )
        end
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
      # Executes Search API call (/v1/search endpoint)
      #
      # @param query [String] Search query
      # @param max_results [Integer, nil] Maximum results to return
      # @param search_domain_filter [Array<String>, nil] Domain filter
      # @param search_recency_filter [String, nil] Recency filter
      # @param return_citations [Boolean, nil] Include citations
      # @param return_images [Boolean, nil] Include images
      # @param return_related_questions [Boolean, nil] Include related questions
      # @return [Hash] Formatted search result
      # @private
      #
      def call_search_api(query:, max_results:, search_domain_filter:, search_recency_filter:,
                          return_citations:, return_images:, return_related_questions:)
        # Build Search API request body
        body = {
          query: query,
          model: @model  # Search API requires model parameter
        }

        # Add max_results (use call-time override or initialize default)
        effective_max_results = max_results || @max_results
        body[:max_results] = effective_max_results if effective_max_results

        # Add optional return parameters
        body[:return_citations] = return_citations if return_citations.is_a?(TrueClass)
        body[:return_images] = return_images if return_images.is_a?(TrueClass)
        body[:return_related_questions] = return_related_questions if return_related_questions.is_a?(TrueClass)

        # Add web search options using common code with validation fallback
        if search_domain_filter || search_recency_filter
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
              raise
            end
          end
        end

        # Execute search using HttpClient with api_type parameter
        result = @http_client.make_api_call(body, api_type: "search")

        # Format result using common parser
        RAAF::Perplexity::ResultParser.format_search_result(
          result,
          include_search_results_in_content: @include_search_results_in_content
        )
      end

      ##
      # Executes Chat API call (/v1/chat/completions endpoint)
      #
      # @param query [String] Search query
      # @param search_domain_filter [Array<String>, nil] Domain filter
      # @param search_recency_filter [String, nil] Recency filter
      # @param temperature [Float, nil] Temperature override
      # @param top_p [Float, nil] Top P override
      # @param presence_penalty [Float, nil] Presence penalty override
      # @param frequency_penalty [Float, nil] Frequency penalty override
      # @return [Hash] Formatted search result
      # @private
      #
      def call_chat_api(query:, search_domain_filter:, search_recency_filter:,
                        temperature:, top_p:, presence_penalty:, frequency_penalty:)
        # Build messages for Perplexity
        messages = [{ role: "user", content: query }]

        # Build request body for Perplexity API
        body = {
          model: @model,
          messages: messages
        }

        # Add optional parameters, preferring call-time values over defaults
        body[:max_tokens] = @max_tokens if @max_tokens

        # Temperature and sampling parameters (call-time override instance defaults)
        body[:temperature] = temperature.nil? ? @temperature : temperature if temperature || @temperature
        body[:top_p] = top_p.nil? ? @top_p : top_p if (top_p || @top_p)
        body[:presence_penalty] = presence_penalty.nil? ? @presence_penalty : presence_penalty if (presence_penalty || @presence_penalty)
        body[:frequency_penalty] = frequency_penalty.nil? ? @frequency_penalty : frequency_penalty if (frequency_penalty || @frequency_penalty)

        # Other advanced parameters
        body[:response_format] = @response_format if @response_format
        body[:reasoning_effort] = @reasoning_effort if @reasoning_effort
        body[:language_preference] = @language_preference if @language_preference

        # Add web search options using common code with validation fallback
        if search_domain_filter || search_recency_filter
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
              raise
            end
          end
        end

        # Execute search using HttpClient directly
        result = @http_client.make_api_call(body)

        # Format result using common parser
        RAAF::Perplexity::ResultParser.format_search_result(
          result,
          include_search_results_in_content: @include_search_results_in_content
        )
      end

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
      # Normalizes filter value by converting empty strings and empty arrays to nil
      #
      # @param value [Object] The filter value to normalize
      # @return [Object, nil] Normalized value or nil if empty
      #
      def normalize_filter(value)
        return nil if value.nil?
        return nil if value.is_a?(String) && value.strip.empty?
        return nil if value.is_a?(Array) && value.empty?

        value
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
