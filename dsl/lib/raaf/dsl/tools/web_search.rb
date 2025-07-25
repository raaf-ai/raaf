# frozen_string_literal: true

# Web Search tool that integrates with OpenAI's hosted web search
#
# This tool uses OpenAI's web search functionality via the Responses API
# and provides configurable options for location-specific searches and
# search context size.
#
# @example Basic usage in an agent
#   class MyAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::AgentDsl
#
#     uses_tool :web_search
#   end
#
# @example With custom configuration
#   class MyAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::AgentDsl
#
#     uses_tool :web_search,
#       user_location: "New York, NY",
#       search_context_size: "high"
#   end
#
module RAAF
  module DSL
    module Tools
      class WebSearch < Base
        # Valid search context size options
        VALID_CONTEXT_SIZES = %w[low medium high].freeze

        # Default configuration
        DEFAULT_CONFIG = {
          user_location: nil,
          search_context_size: "medium"
        }.freeze

        def initialize(options = {})
          super(DEFAULT_CONFIG.merge(options || {}))
          validate_options!
        end

        # Returns the standardized tool name for web search functionality
        #
        # This method provides the canonical name used to identify this tool
        # within the AI Agent DSL framework. The name is used for tool registration,
        # configuration lookup, and OpenAI function calling integration.
        #
        # @return [String] The tool name "web_search"
        #
        def tool_name
          "web_search"
        end

        protected

        def build_tool_definition
          {
            type: "web_search",
            description: "Search the web for current information and real-time data",
            parameters: {
              type: "object",
              properties: {
                query: {
                  type: "string",
                  description: "The search query to execute"
                }
              },
              required: ["query"],
              additionalProperties: false
            }
          }
        end

        private

        def validate_options!
          return unless options[:search_context_size] && !VALID_CONTEXT_SIZES.include?(options[:search_context_size])

          raise ArgumentError,
                "Invalid search_context_size: #{options[:search_context_size]}. Must be one of: #{VALID_CONTEXT_SIZES.join(', ')}"
        end

        # Application metadata for enhanced tool definition
        def application_metadata
          metadata = {}

          metadata[:user_location] = options[:user_location] if options[:user_location]

          metadata[:search_context_size] = options[:search_context_size]
          metadata
        end
      end
    end
  end
end
