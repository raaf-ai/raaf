# frozen_string_literal: true

require_relative "../logging"
require_relative "../errors"

module OpenAIAgents
  module Models
    ##
    # Abstract base class for all model provider implementations
    #
    # This class defines the interface that all LLM providers must implement
    # to work with the OpenAI Agents framework. It provides:
    # - Standard method signatures for chat and streaming completions
    # - Common error handling for API responses
    # - Tool preparation and validation
    # - Model validation against supported models
    #
    # Provider implementations handle the specifics of communicating with
    # different AI services (OpenAI, Anthropic, Groq, etc.) while presenting
    # a unified interface to the rest of the framework.
    #
    # @abstract Subclass and implement the required methods
    #
    # @example Implementing a custom provider
    #   class MyProvider < ModelInterface
    #     def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
    #       # Implementation specific to your API
    #     end
    #     
    #     def supported_models
    #       ["my-model-v1", "my-model-v2"]
    #     end
    #     
    #     def provider_name
    #       "MyProvider"
    #     end
    #   end
    #
    class ModelInterface
      include Logger
      
      ##
      # Initialize a new model provider
      #
      # @param api_key [String, nil] API key for authentication
      # @param api_base [String, nil] Custom API base URL
      # @param options [Hash] Additional provider-specific options
      #
      # @example Initialize with API key
      #   provider = MyProvider.new(api_key: ENV['MY_API_KEY'])
      #
      # @example Initialize with custom endpoint
      #   provider = MyProvider.new(
      #     api_key: "key",
      #     api_base: "https://custom.api.com/v1"
      #   )
      #
      def initialize(api_key: nil, api_base: nil, **options)
        @api_key = api_key
        @api_base = api_base
        @options = options
      end

      ##
      # Execute a chat completion request
      #
      # @abstract Must be implemented by subclasses
      #
      # @param messages [Array<Hash>] Conversation messages with :role and :content
      # @param model [String] Model identifier (e.g., "gpt-4", "claude-3")
      # @param tools [Array<Hash>, nil] Tool definitions for function calling
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional provider-specific parameters
      #
      # @return [Hash] Response in standardized format with choices, usage, etc.
      #
      # @raise [NotImplementedError] If called on base class
      # @raise [AuthenticationError] If API key is invalid
      # @raise [RateLimitError] If rate limit exceeded
      # @raise [APIError] For other API errors
      #
      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        raise NotImplementedError, "Subclasses must implement chat_completion"
      end

      ##
      # Execute a streaming chat completion request
      #
      # @abstract Must be implemented by subclasses
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param block [Proc] Block to yield chunks to
      #
      # @yield [chunk] Yields response chunks as they arrive
      # @yieldparam chunk [Hash] Partial response data
      #
      # @raise [NotImplementedError] If called on base class
      #
      def stream_completion(messages:, model:, tools: nil, &block)
        raise NotImplementedError, "Subclasses must implement stream_completion"
      end

      ##
      # Get list of supported models for this provider
      #
      # @abstract Must be implemented by subclasses
      #
      # @return [Array<String>] List of supported model identifiers
      #
      # @example
      #   provider.supported_models
      #   # => ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"]
      #
      def supported_models
        raise NotImplementedError, "Subclasses must implement supported_models"
      end

      ##
      # Get the human-readable provider name
      #
      # @abstract Must be implemented by subclasses
      #
      # @return [String] Provider name (e.g., "OpenAI", "Anthropic")
      #
      def provider_name
        raise NotImplementedError, "Subclasses must implement provider_name"
      end

      protected

      ##
      # Validate that a model is supported by this provider
      #
      # @param model [String] Model identifier to validate
      # @raise [ArgumentError] If model is not supported
      #
      def validate_model(model)
        return if supported_models.include?(model)

        raise ArgumentError, "Model '#{model}' not supported by #{provider_name}"
      end

      ##
      # Prepare tools for API submission
      #
      # This method converts various tool formats (FunctionTool, Hash, etc.)
      # into the standardized format expected by AI provider APIs.
      #
      # @param tools [Array<FunctionTool, Hash>, nil] Tools to prepare
      # @return [Array<Hash>, nil] Prepared tool definitions or nil
      #
      # @example Tool preparation
      #   tools = [
      #     FunctionTool.new(method(:search)),
      #     { type: "web_search" }
      #   ]
      #   prepared = prepare_tools(tools)
      #   # => [
      #   #   { type: "function", name: "search", function: {...} },
      #   #   { type: "web_search" }
      #   # ]
      #
      def prepare_tools(tools)
        return nil if tools.nil? || tools.empty?

        prepared = tools.map do |tool|
          case tool
          when Hash
            tool
          when FunctionTool
            tool_hash = tool.to_h
            # DEBUG: Log the tool definition being sent to OpenAI
            log_debug_tools("Preparing tool for OpenAI API",
              tool_name: tool_hash.dig(:function, :name),
              tool_type: tool_hash[:type],
              has_parameters: !tool_hash.dig(:function, :parameters).nil?,
              properties_count: tool_hash.dig(:function, :parameters, :properties)&.keys&.length || 0,
              required_count: tool_hash.dig(:function, :parameters, :required)&.length || 0
            )
            tool_hash
          when OpenAIAgents::Tools::WebSearchTool, OpenAIAgents::Tools::HostedFileSearchTool, OpenAIAgents::Tools::HostedComputerTool
            tool.to_tool_definition
          else
            raise ArgumentError, "Invalid tool type: #{tool.class}"
          end
        end

        # DEBUG: Log the final prepared tools
        log_debug_tools("Final tools prepared for OpenAI API",
          tools_count: prepared.length,
          tool_names: prepared.map { |t| t.dig(:function, :name) || t[:type] }.compact
        )

        prepared
      end

      ##
      # Handle API error responses
      #
      # This method provides standardized error handling across all providers,
      # converting HTTP error codes into appropriate exception types.
      #
      # @param response [Net::HTTPResponse] The error response
      # @param provider [String] Provider name for error messages
      #
      # @raise [AuthenticationError] For 401 errors
      # @raise [RateLimitError] For 429 errors  
      # @raise [ServerError] For 5xx errors
      # @raise [APIError] For other errors
      #
      def handle_api_error(response, provider)
        case response.code.to_i
        when 401
          raise AuthenticationError, "Invalid API key for #{provider}"
        when 429
          raise RateLimitError, "Rate limit exceeded for #{provider}"
        when 500..599
          raise ServerError, "Server error from #{provider}: #{response.code}"
        else
          raise APIError, "API error from #{provider}: #{response.code} - #{response.body}"
        end
      end
    end

    ##
    # Raised when API authentication fails
    class AuthenticationError < Error; end
    
    ##
    # Raised when API rate limits are exceeded
    class RateLimitError < Error; end
    
    ##
    # Raised for server-side errors (5xx status codes)
    class ServerError < Error; end
    
    ##
    # Raised for general API errors
    class APIError < Error; end
  end
end
