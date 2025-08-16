# frozen_string_literal: true

require "raaf-dsl"

module RAAF
  module Tools
    module Native
      # Native OpenAI Web Search Tool - Clean implementation using new DSL
      #
      # Provides web search capabilities through OpenAI's hosted web search service.
      # This tool is executed natively by OpenAI's infrastructure and does not require
      # local implementation of the search logic.
      #
      # @example Basic usage in agent
      #   agent.add_tool(RAAF::Tools::Native::WebSearch.new)
      #
      # @example With custom configuration
      #   tool = RAAF::Tools::Native::WebSearch.new(
      #     user_location: "San Francisco, CA",
      #     search_context_size: "high"
      #   )
      #
      class WebSearch < RAAF::DSL::Tools::Tool::Native
        tool_type "web_search"

        # Initialize web search tool with OpenAI native configuration
        #
        # @param options [Hash] Configuration options
        # @option options [String, Hash] :user_location User location for location-aware search
        # @option options [String] :search_context_size Search context size ("low", "medium", "high")
        #
        def initialize(options = {})
          @user_location = normalize_user_location(options[:user_location])
          @search_context_size = validate_search_context_size(options[:search_context_size] || "medium")
          
          super(options.merge(
            type: "web_search",
            web_search: {
              user_location: @user_location,
              search_context_size: @search_context_size
            }.compact
          ))
        end

        # Tool configuration for OpenAI agents
        def to_tool_definition
          {
            type: "web_search",
            web_search: {
              user_location: @user_location,
              search_context_size: @search_context_size
            }.compact
          }
        end

        # Tool name for agent registration
        def name
          "web_search"
        end

        # Native tools are always enabled for OpenAI
        def enabled?
          true
        end

        # Description for tool registry
        def description
          "Search the web for current information using OpenAI's hosted web search"
        end

        private

        # Normalize user location input
        def normalize_user_location(location)
          return nil if location.nil?

          case location
          when String
            # Support simple string format like "San Francisco, CA"
            location
          when Hash
            # Support structured format like {"city" => "New York", "country" => "US"}
            location
          else
            raise ArgumentError, "user_location must be a String or Hash"
          end
        end

        # Validate search context size
        def validate_search_context_size(size)
          valid_sizes = %w[low medium high]
          unless valid_sizes.include?(size)
            raise ArgumentError, "search_context_size must be one of: #{valid_sizes.join(", ")}"
          end

          size
        end
      end
    end
  end
end