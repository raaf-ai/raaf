# frozen_string_literal: true

require "securerandom"
require "logger"
require "net/http"
require_relative "../logging"
require_relative "../errors"

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

      # Retry configuration constants
      DEFAULT_MAX_ATTEMPTS = 5  # Increased from 3 to 5 for better resilience
      DEFAULT_BASE_DELAY = 1.0 # seconds
      DEFAULT_MAX_DELAY = 60.0 # seconds (increased from 30 to accommodate 5 retries)
      DEFAULT_MULTIPLIER = 2.0
      DEFAULT_JITTER = 0.1 # 10% jitter

      # Common retryable exceptions
      RETRYABLE_EXCEPTIONS = [
        Errno::ECONNRESET,
        Errno::ECONNREFUSED,
        Errno::ETIMEDOUT,
        Net::ReadTimeout,
        Net::WriteTimeout,
        Net::OpenTimeout,
        Net::HTTPTooManyRequests,
        Net::HTTPServiceUnavailable,
        Net::HTTPGatewayTimeout,
        ServerError,  # Retry on server errors (500, 502, 503, 504, etc.)
        ServiceUnavailableError  # Retry on gateway/proxy errors (502, 503, 504)
      ].freeze

      # HTTP status codes that should trigger retry
      RETRYABLE_STATUS_CODES = [408, 429, 500, 502, 503, 504].freeze

      attr_accessor :retry_config

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
        @retry_config = default_retry_config
      end

      ##
      # Execute a chat completion request with automatic retry
      #
      # This method automatically wraps the provider's implementation with retry logic,
      # ensuring consistent and reliable behavior across all providers.
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
        with_retry(:chat_completion) do
          perform_chat_completion(messages: messages, model: model, tools: tools, stream: stream, **kwargs)
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

      protected

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
      # Default retry configuration
      #
      # @return [Hash] Default retry configuration hash
      #
      def default_retry_config
        {
          max_attempts: DEFAULT_MAX_ATTEMPTS,
          base_delay: DEFAULT_BASE_DELAY,
          max_delay: DEFAULT_MAX_DELAY,
          multiplier: DEFAULT_MULTIPLIER,
          jitter: DEFAULT_JITTER,
          exceptions: RETRYABLE_EXCEPTIONS.dup,
          status_codes: RETRYABLE_STATUS_CODES.dup,
          logger: nil # Use RAAF's logger instead
        }
      end

      ##
      # Execute a block with retry logic
      #
      # @param method_name [Symbol, String] Name of the method being retried (for logging)
      # @yield Block to execute with retry logic
      # @return Result of the yielded block
      #
      def with_retry(method_name = nil)
        @retry_config ||= default_retry_config
        attempts = 0

        loop do
          attempts += 1

          begin
            result = yield

            # Check for HTTP responses that need retry
            raise RetryableError.new("HTTP #{result.code}", result) if should_retry_response?(result)

            return result
          rescue *@retry_config[:exceptions] => e
            handle_retry_attempt(method_name, attempts, e)
          rescue StandardError => e
            # Check if this is a wrapped HTTP error we should retry
            raise unless retryable_error?(e)

            handle_retry_attempt(method_name, attempts, e)

            # Non-retryable error, re-raise immediately
          end
        end
      end

      ##
      # Handle a retry attempt
      #
      # @param method_name [Symbol, String] Method being retried
      # @param attempts [Integer] Current attempt number
      # @param error [Exception] The error that triggered the retry
      #
      def handle_retry_attempt(method_name, attempts, error)
        if attempts >= @retry_config[:max_attempts]
          log_retry_failure(method_name, attempts, error)
          raise
        end

        delay = calculate_delay(attempts)
        log_retry_attempt(method_name, attempts, error, delay)
        sleep(delay)
      end

      ##
      # Calculate delay for exponential backoff with jitter
      #
      # @param attempt [Integer] Current attempt number
      # @return [Float] Delay in seconds
      #
      def calculate_delay(attempt)
        # Exponential backoff with jitter
        base = @retry_config[:base_delay] * (@retry_config[:multiplier]**(attempt - 1))

        # Cap at max delay
        delay = [base, @retry_config[:max_delay]].min

        # Add jitter (±jitter%)
        jitter_amount = delay * @retry_config[:jitter]
        delay + (rand * 2 * jitter_amount) - jitter_amount
      end

      ##
      # Check if HTTP response should trigger a retry
      #
      # @param response [Object] HTTP response object
      # @return [Boolean] Whether response should be retried
      #
      def should_retry_response?(_response)
        # Let providers handle their own HTTP error responses
        # The retry logic should focus on network-level exceptions
        false
      end

      ##
      # Check if error message indicates a retryable condition
      #
      # @param error [Exception] The error to check
      # @return [Boolean] Whether error should be retried
      #
      def retryable_error?(error)
        error_message = error.message.to_s.downcase

        retryable_patterns = [
          /rate limit/i,
          /too many requests/i,
          /service unavailable/i,
          /gateway timeout/i,
          /connection reset/i,
          /timeout/i,
          /temporarily unavailable/i
        ]

        retryable_patterns.any? { |pattern| error_message.match?(pattern) }
      end

      ##
      # Log retry attempt
      #
      # @param method [Symbol, String] Method being retried
      # @param attempt [Integer] Current attempt number
      # @param error [Exception] The error that triggered retry
      # @param delay [Float] Delay before next attempt
      #
      def log_retry_attempt(method, attempt, error, delay)
        # Calculate next delay for informational logging (if not at max attempts)
        next_delay = if attempt < @retry_config[:max_attempts]
                       calculate_delay(attempt + 1)
                     end

        log_warn(
          "Retry attempt #{attempt}/#{@retry_config[:max_attempts]} for #{method || "operation"}",
          error_class: error.class.name,
          error_message: error.message,
          current_delay_seconds: delay.round(2),
          next_delay_seconds: next_delay&.round(2),
          backoff_strategy: "exponential with #{(@retry_config[:jitter] * 100).to_i}% jitter",
          base_delay: @retry_config[:base_delay],
          multiplier: @retry_config[:multiplier],
          max_delay: @retry_config[:max_delay]
        )
      end

      ##
      # Log retry failure
      #
      # @param method [Symbol, String] Method that failed
      # @param attempts [Integer] Total number of attempts made
      # @param error [Exception] Final error
      #
      def log_retry_failure(method, attempts, error)
        log_error(
          "All #{attempts} retry attempts failed for #{method || "operation"}",
          error_class: error.class.name,
          error_message: error.message
        )
      end

      # Custom error class for retryable HTTP responses
      class RetryableError < StandardError

        attr_reader :response

        def initialize(message, response = nil)
          super(message)
          @response = response
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
