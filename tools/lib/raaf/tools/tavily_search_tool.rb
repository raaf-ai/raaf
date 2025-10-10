# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module RAAF
  module Tools
    ##
    # Tavily Search Tool - Web search using Tavily's API
    #
    # Provides advanced web search with minimal boilerplate.
    # Supports search depth control, domain filtering, and AI-generated summaries.
    #
    # @example Basic usage
    #   tool = RAAF::Tools::TavilySearchTool.new
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
    class TavilySearchTool
      ENDPOINT = "https://api.tavily.com/search"
      DEFAULT_TIMEOUT = 30

      ##
      # Initialize Tavily search tool
      #
      # @param api_key [String, nil] Tavily API key (defaults to TAVILY_API_KEY env var)
      # @param timeout [Integer] Request timeout in seconds
      #
      def initialize(api_key: nil, timeout: DEFAULT_TIMEOUT)
        @api_key = api_key || ENV["TAVILY_API_KEY"]
        @timeout = timeout
      end

      ##
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
          api_key: @api_key,
          query: query,
          search_depth: search_depth,
          max_results: max_results,
          include_answer: include_answer,
          include_raw_content: false
        }

        # Add domain filters if provided
        params[:include_domains] = include_domains if include_domains.any?
        params[:exclude_domains] = exclude_domains if exclude_domains.any?

        response = post_json(params)

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
      rescue StandardError => e
        {
          success: false,
          error: "Search failed",
          error_type: "general_error",
          message: e.message,
          backtrace: e.backtrace.first(5)
        }
      end

      ##
      # Check if tool is enabled (has API key)
      #
      # @return [Boolean]
      #
      def enabled?
        !@api_key.nil? && !@api_key.empty?
      end

      private

      ##
      # POST JSON data to Tavily API
      #
      # @param params [Hash] Request parameters
      # @return [Hash] Parsed response
      #
      def post_json(params)
        uri = URI(ENDPOINT)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @timeout

        request = Net::HTTP::Post.new(uri.path, {"Content-Type" => "application/json"})
        request.body = JSON.generate(params)

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          JSON.parse(response.body)
        else
          { error: "HTTP #{response.code}: #{response.message}" }
        end
      rescue JSON::ParserError => e
        { error: "Invalid JSON response: #{e.message}" }
      rescue StandardError => e
        { error: "Request failed: #{e.message}" }
      end
    end
  end
end
