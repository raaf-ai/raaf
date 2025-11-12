# frozen_string_literal: true

require "securerandom"
require "logger"
require "net/http"
require_relative "../logging"
require_relative "../errors"
require_relative "../throttler"
require_relative "../throttle_config"

module RAAF

  module Models

    ##
    # Abstract base class for all model provider implementations
    #
    # This class defines the interface that all LLM providers must implement
    # to work with the RAAF framework. It provides:
    # - Standard method signatures for chat and streaming completions
    # - Common error handling for API responses
    # - Tool preparation and validation
    # - Model validation against supported models
    # - Universal handoff support via function calling
    # - Automatic Responses API compatibility
    # - Built-in retry logic with exponential backoff
    #
    # Provider implementations handle the specifics of communicating with
    # different AI services (OpenAI, Anthropic, Groq, etc.) while presenting
    # a unified interface to the rest of the framework.
    #
    # @abstract Subclass and implement the required methods
    #
    # @example Implementing a custom provider
    #   class MyProvider < ModelInterface
    #     def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
    #       # Implementation specific to your API
    #       # No need to add retry logic - it's built in!
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
      include RetryHandler
      include Throttler

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
        @rate_limiter = nil
        @rate_limiter_enabled = false
        initialize_retry_config
        initialize_throttle_config
        auto_configure_throttle
      end

      ##
      # Execute a chat completion request with automatic retry and rate limiting
      #
      # This method automatically wraps the provider's implementation with:
      # 1. Rate limiting (if enabled) - prevents exceeding provider RPM limits
      # 2. Throttling (if enabled) - legacy token bucket implementation
      # 3. Retry logic - handles transient failures
      #
      # @param messages [Array<Hash>] Conversation messages with :role and :content
      # @param model [String] Model identifier (e.g., "gpt-4", "claude-3")
      # @param tools [Array<Hash>, nil] Tool definitions for function calling
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional provider-specific parameters
      #
      # @return [Hash] Response in standardized format with choices, usage, etc.
      #
      # @raise [AuthenticationError] If API key is invalid
      # @raise [RateLimitError] If rate limit exceeded
      # @raise [APIError] For other API errors
      #
      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        with_rate_limiting(:chat_completion) do
          with_throttle(:chat_completion) do
            with_retry(:chat_completion) do
              perform_chat_completion(messages: messages, model: model, tools: tools, stream: stream, **kwargs)
            end
          end
        end
      end

      ##
      # Execute a streaming chat completion request with automatic retry
      #
      # This method automatically wraps the provider's implementation with retry logic.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param block [Proc] Block to yield chunks to
      #
      # @yield [chunk] Yields response chunks as they arrive
      # @yieldparam chunk [Hash] Partial response data
      #
      def stream_completion(messages:, model:, tools: nil, &block)
        with_retry(:stream_completion) do
          perform_stream_completion(messages: messages, model: model, tools: tools, &block)
        end
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

      ##
      # Default implementation of responses_completion with automatic retry
      #
      # This method provides automatic Responses API compatibility for any
      # provider that implements perform_chat_completion. It converts between the
      # different API formats to ensure universal handoff support.
      #
      # @example Basic usage with handoff tools
      #   response = provider.responses_completion(
      #     messages: [{ role: "user", content: "I need billing help" }],
      #     model: "gpt-4",
      #     tools: [{
      #       type: "function",
      #       name: "transfer_to_billing",
      #       function: {
      #         name: "transfer_to_billing",
      #         description: "Transfer to billing agent",
      #         parameters: { type: "object", properties: {} }
      #       }
      #     }]
      #   )
      #   # Returns: { output: [...], usage: {...}, model: "gpt-4" }
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param stream [Boolean] Whether to stream response
      # @param previous_response_id [String, nil] Previous response ID for continuation
      # @param input [Array<Hash>, nil] Input items for Responses API
      # @param **kwargs [Hash] Additional parameters
      #
      # @return [Hash] Response in Responses API format with :output, :usage, :model, :id
      #
      def responses_completion(messages:, model:, tools: nil, stream: false, previous_response_id: nil, input: nil,
                               **kwargs)
        with_rate_limiting(:responses_completion) do
          with_retry(:responses_completion) do
            log_debug("🔧 INTERFACE: Converting chat_completion to responses_completion",
                      provider: provider_name,
                      has_tools: !tools.nil?,
                      tools_count: tools&.size || 0)

            # Convert input items back to messages if needed
            actual_messages = if input&.any?
                                convert_input_to_messages(input, messages)
                              else
                                messages
                              end

            # Call the provider's chat_completion method
            response = perform_chat_completion(
              messages: actual_messages,
              model: model,
              tools: tools,
              stream: stream,
              **kwargs
            )

            # Convert response to Responses API format
            converted = convert_chat_to_responses_format(response)
            converted
          end
        end
      end

      ##
      # Check if provider supports handoffs
      #
      # By default, handoff support is available if the provider supports
      # function calling (i.e., accepts tools parameter).
      #
      # @return [Boolean] True if handoffs are supported, false otherwise
      #
      def supports_handoffs?
        supports_function_calling?
      end

      ##
      # Check if provider supports function calling
      #
      # This method inspects the perform_chat_completion method signature to determine
      # if it accepts a tools parameter, which indicates function calling support.
      #
      # @return [Boolean] True if function calling is supported, false otherwise
      #
      def supports_function_calling?
        method(:perform_chat_completion).parameters.any? { |param| param[1] == :tools }
      end

      ##
      # Get provider capabilities
      #
      # Returns a comprehensive hash of provider capabilities including
      # API support, streaming, function calling, and handoff support.
      #
      # @return [Hash] Capability flags with keys:
      #   - :responses_api - Whether provider supports Responses API
      #   - :chat_completion - Whether provider supports Chat Completions API
      #   - :streaming - Whether provider supports streaming
      #   - :function_calling - Whether provider supports function calling
      #   - :handoffs - Whether provider supports handoffs
      #
      def capabilities
        {
          responses_api: respond_to?(:responses_completion),
          chat_completion: respond_to?(:chat_completion),
          streaming: respond_to?(:stream_completion),
          function_calling: supports_function_calling?,
          handoffs: supports_handoffs?
        }
      end

      ##
      # Configure retry behavior for this provider
      #
      # @example Custom retry configuration
      #   provider.configure_retry(
      #     max_attempts: 5,
      #     base_delay: 2.0,
      #     max_delay: 60.0
      #   )
      #
      # @param options [Hash] Retry configuration options
      # @return [self] Returns self for method chaining
      #
      def configure_retry(**options)
        @retry_config ||= default_retry_config
        @retry_config.merge!(options)
        self
      end

      ##
      # Configure rate limiting for this provider
      #
      # Rate limiting uses a token bucket algorithm to prevent exceeding provider RPM limits.
      # This is proactive (prevents rate limits) while retry logic is reactive (handles failures).
      #
      # @example Enable rate limiting with default RPM
      #   provider.configure_rate_limiting(enabled: true)
      #
      # @example Custom RPM limit
      #   provider.configure_rate_limiting(
      #     enabled: true,
      #     requests_per_minute: 60
      #   )
      #
      # @example Custom storage backend
      #   redis_storage = RAAF::RateLimiter::RedisStorage.new
      #   provider.configure_rate_limiting(
      #     enabled: true,
      #     storage: redis_storage
      #   )
      #
      # @param enabled [Boolean] Enable/disable rate limiting (default: false)
      # @param requests_per_minute [Integer, nil] RPM limit (uses provider default if nil)
      # @param storage [RateLimiter::MemoryStorage, RateLimiter::RedisStorage, RateLimiter::RailsCacheStorage, nil] Storage backend (default: MemoryStorage)
      # @return [self] Returns self for method chaining
      #
      def configure_rate_limiting(enabled: false, requests_per_minute: nil, storage: nil)
        @rate_limiter_enabled = enabled

        if enabled
          # Create rate limiter with provider-specific defaults
          @rate_limiter = RAAF::RateLimiter.new(
            provider: rate_limiter_provider_name,
            requests_per_minute: requests_per_minute,
            storage: storage
          )
        else
          @rate_limiter = nil
        end

        self
      end

      ##
      # Get rate limiter status
      #
      # @return [Hash, nil] Rate limiter status or nil if disabled
      #
      def rate_limiter_status
        return nil unless @rate_limiter_enabled && @rate_limiter

        @rate_limiter.status
      end

      ##
      # Reset rate limiter (useful for testing)
      #
      def reset_rate_limiter
        @rate_limiter&.reset!
      end

      protected

      ##
      # Auto-configure throttle from ThrottleConfig defaults
      #
      # Automatically loads default RPM limits based on provider type.
      # Throttling remains disabled by default (opt-in).
      #
      def auto_configure_throttle
        default_rpm = ThrottleConfig.rpm_for_provider(self)
        return unless default_rpm

        # Configure RPM but keep throttling disabled by default
        configure_throttle(rpm: default_rpm, enabled: false)
      end

      ##
      # Execute a chat completion request (to be implemented by subclasses)
      #
      # @abstract Must be implemented by subclasses
      #
      # This is the method that subclasses actually implement. The public
      # chat_completion method wraps this with automatic retry logic.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional provider-specific parameters
      #
      # @return [Hash] Response in standardized format
      #
      # @raise [NotImplementedError] If called on base class
      #
      def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        raise NotImplementedError, "Subclasses must implement perform_chat_completion"
      end

      ##
      # Execute a streaming chat completion request (to be implemented by subclasses)
      #
      # @abstract Must be implemented by subclasses
      #
      # This is the method that subclasses actually implement. The public
      # stream_completion method wraps this with automatic retry logic.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param block [Proc] Block to yield chunks to
      #
      # @yield [chunk] Yields response chunks as they arrive
      #
      # @raise [NotImplementedError] If called on base class
      #
      def perform_stream_completion(messages:, model:, tools: nil, &block)
        raise NotImplementedError, "Subclasses must implement perform_stream_completion"
      end

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
      def prepare_tools(tools)
        return nil if tools.nil? || tools.empty?

        prepared = tools.map do |tool|
          case tool
          when Hash
            tool
          when FunctionTool
            tool_hash = tool.to_h
            # DEBUG: Log the tool definition being sent to API
            log_debug_tools("Preparing tool for API",
                            tool_name: tool_hash.dig(:function, :name),
                            tool_type: tool_hash[:type],
                            has_parameters: !tool_hash.dig(:function, :parameters).nil?,
                            properties_count: tool_hash.dig(:function, :parameters, :properties)&.keys&.length || 0,
                            required_count: tool_hash.dig(:function, :parameters, :required)&.length || 0)

            # Enhanced logging for array parameters to debug "items" property
            tool_hash.dig(:function, :parameters, :properties)&.each do |prop_name, prop_def|
              next unless prop_def[:type] == "array"

              log_debug_tools("Array property debug for #{prop_name}",
                              full_property_definition: prop_def.inspect,
                              has_items_property: prop_def.key?(:items),
                              items_value: prop_def[:items].inspect)
              log_error("Array property '#{prop_name}' has nil items - this will cause API errors!") if prop_def[:items].nil?
            end

            tool_hash
          else
            # Check if this is a Tools module class when available
            raise ArgumentError, "Invalid tool type: #{tool.class}" unless defined?(RAAF::Tools)

            if tool.is_a?(RAAF::Tools::WebSearchTool) ||
               tool.is_a?(RAAF::Tools::HostedFileSearchTool) ||
               tool.is_a?(RAAF::Tools::HostedComputerTool)
              tool.to_tool_definition
            else
              raise ArgumentError, "Invalid tool type: #{tool.class}"
            end
          end
        end

        # DEBUG: Log the final prepared tools
        log_debug_tools("Final tools prepared for API",
                        tools_count: prepared.length,
                        tool_names: prepared.map { |t| t.dig(:function, :name) || t[:type] }.compact)

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

      ##
      # Convert Responses API input items to messages
      #
      # @param input [Array<Hash>] Input items from Responses API
      # @param base_messages [Array<Hash>] Base conversation messages
      # @return [Array<Hash>] Combined messages in Chat Completions format
      #
      def convert_input_to_messages(input, base_messages)
        # Start with base messages
        messages = base_messages.dup

        # Process input items
        input.each do |item|
          case item[:type] || item["type"]
          when "message"
            messages << {
              role: item[:role] || item["role"],
              content: item[:content] || item["content"]
            }
          when "function_call_output"
            messages << {
              role: "tool",
              tool_call_id: item[:call_id] || item["call_id"],
              content: item[:output] || item["output"]
            }
          end
        end

        messages
      end

      ##
      # Convert Chat Completions response to Responses API format
      #
      # @param response [Hash] Chat Completions API response
      # @return [Hash] Responses API format with :output, :usage, :model, :id
      #
      def convert_chat_to_responses_format(response)
        choice = response.dig("choices", 0) || response.dig(:choices, 0)
        return { output: [] } unless choice

        message = choice["message"] || choice[:message]
        return { output: [] } unless message

        output = []

        # Add text content
        if message["content"] || message[:content]
          content = message["content"] || message[:content]
          output << {
            type: "message",
            role: "assistant",
            content: content
          }
        end

        # Add tool calls
        if message["tool_calls"] || message[:tool_calls]
          tool_calls = message["tool_calls"] || message[:tool_calls]
          tool_calls.each do |tool_call|
            output << {
              type: "function_call",
              id: tool_call["id"] || tool_call[:id],
              name: tool_call.dig("function", "name") || tool_call.dig(:function, :name),
              arguments: tool_call.dig("function", "arguments") || tool_call.dig(:function, :arguments)
            }
          end
        end

        # Return in Responses API format with all necessary fields
        responses_format = {
          output: output,
          usage: response["usage"] || response[:usage],
          model: response["model"] || response[:model],
          id: response["id"] || response[:id] || SecureRandom.uuid
        }

        # CRITICAL: Preserve provider metadata (e.g., search_results from Perplexity)
        # This metadata is needed by downstream pipeline stages
        provider_metadata = response["metadata"] || response[:metadata]
        if provider_metadata.is_a?(Hash) && provider_metadata.any?
          responses_format[:metadata] = provider_metadata
        end

        responses_format
      end

      private

      ##
      # Wrap API call with rate limiting if enabled
      #
      # @param operation_name [Symbol] Operation identifier
      # @yield Block to execute within rate limit
      # @return Result of the block
      #
      def with_rate_limiting(operation_name)
        if @rate_limiter_enabled && @rate_limiter
          @rate_limiter.acquire { yield }
        else
          yield
        end
      end

      ##
      # Get provider name for rate limiter
      #
      # Subclasses can override to provide specific names (e.g., "gemini", "openai")
      # Defaults to the provider_name method lowercased
      #
      # @return [String] Provider name for rate limiter configuration
      #
      def rate_limiter_provider_name
        provider_name.downcase.gsub(/\s+/, "_")
      end

      # All retry logic now handled by RetryHandler module

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
