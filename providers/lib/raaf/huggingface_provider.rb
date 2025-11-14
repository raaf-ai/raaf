# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
# Interface is required from raaf-core gem

module RAAF
  module Models
    ##
    # Hugging Face Inference Providers implementation
    #
    # Provides access to hundreds of models through Hugging Face's unified
    # inference routing system. The API is OpenAI-compatible with support
    # for function calling, streaming, and multi-provider routing.
    #
    # Features:
    # - Access to 100+ models via unified endpoint
    # - Automatic provider routing (Cerebras, Groq, Nebius, etc.)
    # - OpenAI-compatible function calling
    # - Streaming responses
    # - Multi-model support with capability detection
    #
    # @example Basic usage
    #   provider = HuggingFaceProvider.new(api_key: ENV["HUGGINGFACE_API_KEY"])
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "deepseek-ai/DeepSeek-R1-0528"
    #   )
    #
    # @example With tools
    #   provider = HuggingFaceProvider.new
    #   response = provider.chat_completion(
    #     messages: messages,
    #     model: "meta-llama/Llama-3-70B-Instruct",
    #     tools: [{
    #       type: "function",
    #       function: {
    #         name: "get_weather",
    #         description: "Get weather for a location",
    #         parameters: { type: "object", properties: {...} }
    #       }
    #     }]
    #   )
    #
    class HuggingFaceProvider < ModelInterface
      include RAAF::Logger

      # Hugging Face Inference Providers API endpoint
      DEFAULT_API_BASE = "https://router.huggingface.co/v1"

      # Verified models with tested capabilities
      # Users can use any model, but these are confirmed working
      SUPPORTED_MODELS = %w[
        deepseek-ai/DeepSeek-R1-0528
        meta-llama/Llama-3-70B-Instruct
        mistralai/Mixtral-8x7B-Instruct-v0.1
        microsoft/phi-4
      ].freeze

      # Models verified to support function calling
      FUNCTION_CALLING_MODELS = %w[
        deepseek-ai/DeepSeek-R1-0528
      ].freeze

      # HTTP timeout accessor for Runner integration
      attr_accessor :http_timeout

      ##
      # Initialize a new Hugging Face provider
      #
      # @param api_key [String, nil] Hugging Face API key (defaults to HUGGINGFACE_API_KEY or HF_TOKEN env var)
      # @param api_base [String, nil] API base URL (defaults to HUGGINGFACE_API_BASE env var or default)
      # @param timeout [Integer, nil] HTTP timeout in seconds (default: 180)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, timeout: nil, **options)
        @api_key = api_key || ENV.fetch("HUGGINGFACE_API_KEY", nil) || ENV.fetch("HF_TOKEN", nil)
        @api_base = api_base || ENV["HUGGINGFACE_API_BASE"] || DEFAULT_API_BASE
        @http_timeout = timeout || ENV.fetch("HUGGINGFACE_TIMEOUT", "180").to_i
        @options = options

        raise RAAF::AuthenticationError, "Hugging Face API key is required" if @api_key.nil? || @api_key.empty?
      end

      ##
      # Performs a chat completion using Hugging Face's Inference Providers API
      #
      # The API is OpenAI-compatible, so minimal format conversion is needed.
      # Returns response directly in OpenAI format.
      #
      # @param messages [Array<Hash>] Conversation messages in OpenAI format
      # @param model [String] Hugging Face model to use (org/model format)
      # @param tools [Array<Hash>, nil] Tools/functions available to the model
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional parameters (max_tokens, temperature, etc.)
      # @return [Hash] Response in OpenAI format
      # @raise [ModelNotFoundError] if model format is invalid
      # @raise [APIError] if the API request fails
      #
      def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        validate_model(model)

        # Build OpenAI-compatible request
        body = {
          model: model,
          messages: messages,
          stream: stream
        }

        # Add tools if present (already OpenAI format)
        if tools && !tools.empty?
          # Warn if model may not support function calling
          unless FUNCTION_CALLING_MODELS.include?(model)
            log_warn("Model '#{model}' may not support function calling. " \
                     "Function calling is confirmed for: #{FUNCTION_CALLING_MODELS.join(', ')}",
                     provider: "HuggingFaceProvider",
                     model: model)
          end

          body[:tools] = prepare_tools(tools)
          body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]
        end

        # Add generation parameters
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:stop] = kwargs[:stop] if kwargs[:stop]

        # Make API call
        response = make_api_call(body)

        # Response is already OpenAI format - return as-is
        response
      end

      ##
      # Streams a chat completion using Server-Sent Events
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Hugging Face model to use
      # @param tools [Array<Hash>, nil] Available tools
      # @yield [Hash] Yields streaming chunks with type, content, and accumulated data
      # @return [Hash] Final response with accumulated content
      #
      def perform_stream_completion(messages:, model:, tools: nil, **kwargs, &block)
        validate_model(model)

        # Build request body
        body = build_request_body(messages, model, tools, **kwargs)
        body[:stream] = true

        accumulated_content = ""
        accumulated_tool_calls = []

        make_streaming_request(body) do |chunk|
          next unless chunk.start_with?("data: ")

          data = chunk[6..].strip

          if data == "[DONE]"
            yield({
              type: "finish",
              finish_reason: "stop",
              accumulated_content: accumulated_content,
              accumulated_tool_calls: accumulated_tool_calls
            }) if block_given?
          else
            begin
              parsed = RAAF::Utils.parse_json(data)

              # Handle content delta
              if parsed.dig("choices", 0, "delta", "content")
                content = parsed["choices"][0]["delta"]["content"]
                accumulated_content += content
                yield({
                  type: "content",
                  content: content,
                  accumulated_content: accumulated_content
                }) if block_given?
              end

              # Handle tool calls delta
              if parsed.dig("choices", 0, "delta", "tool_calls")
                tool_calls = parsed["choices"][0]["delta"]["tool_calls"]
                accumulated_tool_calls.concat(tool_calls)
                yield({
                  type: "tool_calls",
                  tool_calls: tool_calls,
                  accumulated_tool_calls: accumulated_tool_calls
                }) if block_given?
              end
            rescue JSON::ParserError => e
              log_warn("Failed to parse streaming chunk: #{e.message}",
                       provider: "HuggingFaceProvider",
                       chunk: data)
            end
          end
        end

        { content: accumulated_content, tool_calls: accumulated_tool_calls }
      end

      ##
      # Returns list of supported Hugging Face models
      #
      # @return [Array<String>] Verified model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "HuggingFace"
      #
      def provider_name
        "HuggingFace"
      end

      private

      ##
      # Validates model format and logs warnings for unverified models
      #
      # @param model [String] Model name to validate
      # @raise [ArgumentError] if model format is invalid
      # @private
      #
      def validate_model(model)
        # Check for org/model format requirement
        unless model.include?("/")
          raise ArgumentError,
                "Hugging Face models must use format: org/model-name (e.g., 'deepseek-ai/DeepSeek-R1-0528')"
        end

        # Warn if not in verified list
        unless SUPPORTED_MODELS.include?(model)
          log_warn("Model '#{model}' is not in the verified models list. " \
                   "Functionality may vary. Verified models: #{SUPPORTED_MODELS.join(', ')}",
                   provider: "HuggingFaceProvider",
                   model: model)
        end

        true
      end

      ##
      # Builds request body for API call
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model name
      # @param tools [Array<Hash>, nil] Tools
      # @param kwargs [Hash] Additional parameters
      # @return [Hash] Request body
      # @private
      #
      def build_request_body(messages, model, tools, **kwargs)
        body = {
          model: model,
          messages: messages
        }

        # Add tools if present
        if tools && !tools.empty?
          unless FUNCTION_CALLING_MODELS.include?(model)
            log_warn("Model '#{model}' may not support function calling",
                     provider: "HuggingFaceProvider",
                     model: model)
          end

          body[:tools] = prepare_tools(tools)
          body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]
        end

        # Add generation parameters
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:stop] = kwargs[:stop] if kwargs[:stop]

        body
      end

      ##
      # Makes a non-streaming API call
      #
      # @param body [Hash] Request body
      # @return [Hash] Response in OpenAI format
      # @private
      #
      def make_api_call(body)
        uri = URI("#{@api_base}/chat/completions")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @http_timeout
        http.open_timeout = @http_timeout

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)

        response = http.request(request)

        handle_api_error(response, "HuggingFace") unless response.is_a?(Net::HTTPSuccess)

        result = RAAF::Utils.parse_json(response.body)

        # Normalize token usage to canonical format
        if result["usage"]
          normalized_usage = RAAF::Usage::Normalizer.normalize(
            result,
            provider_name: "huggingface",
            model: result["model"] || body[:model]
          )
          result["usage"] = normalized_usage if normalized_usage
        end

        result
      end

      ##
      # Makes a streaming API call with SSE
      #
      # @param body [Hash] Request body
      # @yield [String] Yields SSE chunks
      # @private
      #
      def make_streaming_request(body)
        uri = URI("#{@api_base}/chat/completions")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @http_timeout
        http.open_timeout = @http_timeout

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "text/event-stream"
        request.body = JSON.generate(body)

        http.request(request) do |response|
          handle_api_error(response, "HuggingFace") unless response.is_a?(Net::HTTPSuccess)

          response.read_body do |chunk|
            chunk.each_line do |line|
              yield(line.strip) if block_given? && !line.strip.empty?
            end
          end
        end
      end
    end
  end
end
