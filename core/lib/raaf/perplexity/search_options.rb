# frozen_string_literal: true

require_relative "common"

module RAAF
  module Perplexity
    ##
    # Builder for Perplexity web search options
    #
    # Constructs the web_search_options hash for Perplexity API requests,
    # handling domain filtering and recency filtering with proper validation.
    #
    # @example Basic usage
    #   options = RAAF::Perplexity::SearchOptions.build(
    #     domain_filter: ["ruby-lang.org", "github.com"],
    #     recency_filter: "week"
    #   )
    #   # => { search_domain_filter: ["ruby-lang.org", "github.com"], search_recency_filter: "week" }
    #
    # @example No filters
    #   options = RAAF::Perplexity::SearchOptions.build
    #   # => nil
    #
    # @example Domain filter only
    #   options = RAAF::Perplexity::SearchOptions.build(domain_filter: ["ruby-lang.org"])
    #   # => { search_domain_filter: ["ruby-lang.org"] }
    #
    class SearchOptions
      ##
      # Builds web search options hash for Perplexity API
      #
      # @param domain_filter [Array<String>, nil] Domain names to restrict search to
      # @param recency_filter [String, nil] Time window for results ("hour", "day", "week", "month", "year")
      # @return [Hash, nil] Hash with search options, or nil if no filters specified
      # @raise [ArgumentError] if recency_filter is invalid
      #
      def self.build(domain_filter: nil, recency_filter: nil)
        # Normalize empty strings and empty arrays to nil
        domain_filter = normalize_filter_value(domain_filter)
        recency_filter = normalize_filter_value(recency_filter)

        options = {}

        # Add domain filter if provided
        if domain_filter
          # Convert to array and check if not empty
          domain_array = Array(domain_filter)
          options[:search_domain_filter] = domain_array if domain_array.any?
        end

        # Add and validate recency filter if provided
        if recency_filter
          RAAF::Perplexity::Common.validate_recency_filter(recency_filter)
          options[:search_recency_filter] = recency_filter
        end

        # Return nil if no options specified, otherwise return hash
        options.empty? ? nil : options
      end

      ##
      # Normalizes filter values by converting empty strings and empty arrays to nil
      #
      # @param value [Object] The filter value to normalize
      # @return [Object, nil] Normalized value or nil if empty
      #
      def self.normalize_filter_value(value)
        return nil if value.nil?
        return nil if value.is_a?(String) && value.strip.empty?
        return nil if value.is_a?(Array) && value.empty?

        value
      end
    end
  end
end
