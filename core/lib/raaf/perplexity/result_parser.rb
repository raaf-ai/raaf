# frozen_string_literal: true

module RAAF
  module Perplexity
    ##
    # Parser for Perplexity API responses
    #
    # Extracts content, citations, and web results from Perplexity API responses,
    # providing a consistent interface for both PerplexityProvider and PerplexityTool.
    #
    # @example Extract content
    #   content = RAAF::Perplexity::ResultParser.extract_content(result)
    #   # => "Ruby 3.4 includes performance improvements..."
    #
    # @example Extract citations
    #   citations = RAAF::Perplexity::ResultParser.extract_citations(result)
    #   # => ["https://ruby-lang.org/news", "https://github.com/ruby/ruby"]
    #
    # @example Format complete result
    #   formatted = RAAF::Perplexity::ResultParser.format_search_result(result)
    #   # => {
    #   #      success: true,
    #   #      content: "...",
    #   #      citations: [...],
    #   #      search_results: [...],
    #   #      model: "sonar-pro"
    #   #    }
    #
    class ResultParser
      ##
      # Extracts text content from Perplexity response
      #
      # @param result [Hash] Perplexity API response
      # @return [String, nil] Response content or nil if not found
      #
      def self.extract_content(result)
        result.dig("choices", 0, "message", "content")
      end

      ##
      # Extracts citation URLs from Perplexity response
      #
      # Citations provide source attribution for the information returned.
      # These are direct URLs to the sources Perplexity used.
      #
      # @param result [Hash] Perplexity API response
      # @return [Array<String>] Array of citation URLs (empty if none found)
      #
      def self.extract_citations(result)
        result["citations"] || []
      end

      ##
      # Extracts detailed web results from Perplexity response
      #
      # Web results include structured information about each source:
      # - title: Title of the web page
      # - url: URL of the source
      # - snippet: Excerpt from the source
      #
      # @param result [Hash] Perplexity API response
      # @return [Array<Hash>] Array of web result hashes (empty if none found)
      #
      def self.extract_search_results(result)
        result["search_results"] || []
      end

      ##
      # Formats Perplexity response into standardized result hash
      #
      # Provides a consistent return format for both PerplexityProvider
      # and PerplexityTool with all relevant information extracted.
      #
      # @param result [Hash] Perplexity API response
      # @param include_search_results_in_content [Boolean] Whether to append search results to content
      # @return [Hash] Formatted result with:
      #   - :success [Boolean] Always true for successful API responses
      #   - :content [String] Response text content (optionally with inline search results)
      #   - :citations [Array<String>] Source URLs
      #   - :search_results [Array<Hash>] Detailed source information
      #   - :model [String] Model that generated the response
      #
      def self.format_search_result(result, include_search_results_in_content: false)
        content = extract_content(result)
        search_results = extract_search_results(result)
        citations = extract_citations(result)

        # Optionally append search_results to content for inline extraction
        if include_search_results_in_content && search_results.any?
          content += "\n\n## Search Results\n\n"
          search_results.each_with_index do |sr, idx|
            content += "#{idx + 1}. **#{sr['title']}**\n"
            content += "   URL: #{sr['url']}\n"
            content += "   Snippet: #{sr['snippet']}\n\n"
          end
        elsif include_search_results_in_content && search_results.empty?
          content += "\n\n## Search Results\n\nNo search results were returned for this query.\n"
        end

        {
          success: true,
          content: content,
          citations: citations,
          search_results: search_results,
          model: result["model"]
        }
      end
    end
  end
end
