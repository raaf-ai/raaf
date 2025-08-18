# frozen_string_literal: true

require_relative "../../../../../lib/raaf/tool/api"

module RAAF
  module Tools
    module Unified
      # Tavily Search API Tool
      #
      # Advanced web search using Tavily's API with search depth control,
      # domain filtering, and AI-generated summaries.
      #
      class TavilySearchTool < RAAF::Tool::API
        endpoint "https://api.tavily.com/search"
        api_key_env "TAVILY_API_KEY"
        timeout 30

        configure description: "Search the web using Tavily's advanced search API"

        parameters do
          property :query, type: "string", description: "Search query"
          property :search_depth, type: "string", 
                  enum: ["basic", "advanced"],
                  description: "Search depth (basic or advanced)"
          property :max_results, type: "integer",
                  description: "Maximum number of results (1-20)"
          property :include_answer, type: "boolean",
                  description: "Include AI-generated summary"
          property :include_domains, type: "array",
                  items: { type: "string" },
                  description: "Domains to include in search"
          property :exclude_domains, type: "array",
                  items: { type: "string" },
                  description: "Domains to exclude from search"
          required :query
        end

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

          params[:include_domains] = include_domains unless include_domains.empty?
          params[:exclude_domains] = exclude_domains unless exclude_domains.empty?

          response = post("", json: params)
          format_results(response)
        end

        private

        def format_results(response)
          return response unless response.is_a?(Hash)

          formatted = {
            query: response["query"],
            answer: response["answer"],
            results: response["results"]&.map { |r| format_result(r) }
          }.compact

          formatted
        end

        def format_result(result)
          {
            title: result["title"],
            url: result["url"],
            content: result["content"],
            score: result["score"]
          }.compact
        end
      end
    end
  end
end