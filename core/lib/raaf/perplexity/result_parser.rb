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
    #   #      web_results: [...],
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
      def self.extract_web_results(result)
        result["web_results"] || []
      end

      ##
      # Formats Perplexity response into standardized result hash
      #
      # Provides a consistent return format for both PerplexityProvider
      # and PerplexityTool with all relevant information extracted.
      #
      # @param result [Hash] Perplexity API response
      # @return [Hash] Formatted result with:
      #   - :success [Boolean] Always true for successful API responses
      #   - :content [String] Response text content
      #   - :citations [Array<String>] Source URLs
      #   - :web_results [Array<Hash>] Detailed source information
      #   - :model [String] Model that generated the response
      #
      def self.format_search_result(result)
        {
          success: true,
          content: extract_content(result),
          citations: extract_citations(result),
          web_results: extract_web_results(result),
          model: result["model"]
        }
      end
    end
  end
end
