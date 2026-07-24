# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
# Interface is required from raaf-core gem

module RAAF
  module Models
    ##
    # Base class for providers exposing an OpenAI-compatible chat completions API
    #
    # Many newer model vendors (DeepSeek, Alibaba Qwen/DashScope, Zhipu GLM,
    # Xiaomi MiMo, ...) ship an endpoint that speaks the exact OpenAI
    # `/chat/completions` wire format. Their providers differ only in a handful
    # of constants, so they subclass this base instead of duplicating the HTTP,
    # streaming, and error-handling logic.
    #
    # Subclasses MUST define these constants:
    # - +API_BASE+ [String] default base URL (OpenAI-compatible, ending before /chat/completions)
    # - +SUPPORTED_MODELS+ [Array<String>] whitelisted model ids
    # - +API_KEY_ENV+ [String] environment variable holding the API key
    # - +PROVIDER_DISPLAY_NAME+ [String] human-readable provider name
    # - +USAGE_PROVIDER_KEY+ [String] key passed to the usage normalizer
    #
    # @example Defining a new OpenAI-compatible provider
    #   class MyProvider < OpenAICompatibleProvider
    #     API_BASE = "https://api.example.com/v1"
    #     SUPPORTED_MODELS = %w[example-model].freeze
    #     API_KEY_ENV = "EXAMPLE_API_KEY"
    #     PROVIDER_DISPLAY_NAME = "Example"
    #     USAGE_PROVIDER_KEY = "example"
    #   end
    #
    class OpenAICompatibleProvider < ModelInterface
      ##
      # Initialize a new OpenAI-compatible provider
      #
      # @param api_key [String, nil] API key (defaults to the subclass API_KEY_ENV var)
      # @param api_base [String, nil] API base URL (defaults to the subclass API_BASE)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_key ||= ENV.fetch(self.class::API_KEY_ENV, nil)
        @api_base ||= api_base || self.class::API_BASE

        raise AuthenticationError, "#{provider_name} API key is required" unless @api_key
      end

      ##
      # Performs a chat completion using the vendor's OpenAI-compatible API
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model id to use
      # @param tools [Array<Hash>, nil] Tools/functions available to the model
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional parameters (temperature, max_tokens, etc.)
      # @return [Hash] Response in OpenAI format
      # @raise [ArgumentError] if model is not supported
      # @raise [APIError] if the API request fails
      #
      def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs, &block)
        validate_model(model)

        body = {
          model: model,
          messages: messages,
          stream: stream
        }

        if tools && !tools.empty?
          body[:tools] = prepare_tools(tools)
          body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]
        end

        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:stop] = kwargs[:stop] if kwargs[:stop]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:user] = kwargs[:user] if kwargs[:user]
        body[:response_format] = kwargs[:response_format] if kwargs[:response_format]

        if stream
          stream_response(body, &block)
        else
          make_request(body)
        end
      end

      ##
      # Streams a chat completion
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model id to use
      # @param tools [Array<Hash>, nil] Available tools
      # @param kwargs [Hash] Additional parameters
      # @yield [Hash] Yields streaming chunks
      # @return [Hash] Final accumulated response
      #
      def perform_stream_completion(messages:, model:, tools: nil, **kwargs, &block)
        perform_chat_completion(
          messages: messages,
          model: model,
          tools: tools,
          stream: true,
          **kwargs,
          &block
        )
      end

      ##
      # Returns list of supported models
      #
      # @return [Array<String>] Supported model names
      #
      def supported_models
        self.class::SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] The vendor display name
      #
      def provider_name
        self.class::PROVIDER_DISPLAY_NAME
      end

      private

      ##
      # Handles streaming responses (Server-Sent Events)
      #
      # @param body [Hash] Request body
      # @yield [Hash] Yields streaming chunks with type and content
      # @return [Hash] Final accumulated response
      # @private
      #
      def stream_response(body)
        body[:stream] = true

        accumulated_content = ""
        accumulated_tool_calls = []

        make_streaming_request(body) do |chunk|
          next unless chunk.start_with?("data: ")

          data = chunk[6..].strip

          if data == "[DONE]"
            yield({ type: "done", content: accumulated_content, tool_calls: accumulated_tool_calls }) if block_given?
            next
          end

          begin
            parsed = RAAF::Utils.parse_json(data)

            if parsed.dig("choices", 0, "delta", "content")
              content = parsed["choices"][0]["delta"]["content"]
              accumulated_content += content
              if block_given?
                yield({ type: "content", content: content, accumulated_content: accumulated_content })
              end
            end

            if parsed.dig("choices", 0, "delta", "tool_calls")
              tool_calls = parsed["choices"][0]["delta"]["tool_calls"]
              accumulated_tool_calls.concat(tool_calls)
              if block_given?
                yield({ type: "tool_calls", tool_calls: tool_calls, accumulated_tool_calls: accumulated_tool_calls })
              end
            end

            if parsed.dig("choices", 0, "finish_reason") && block_given?
              yield({
                type: "finish",
                finish_reason: parsed["choices"][0]["finish_reason"],
                content: accumulated_content,
                tool_calls: accumulated_tool_calls
              })
            end
          rescue JSON::ParserError => e
            log_debug("Failed to parse streaming chunk: #{e.message}",
                      provider: self.class.name,
                      error_class: e.class.name)
          end
        end

        { content: accumulated_content, tool_calls: accumulated_tool_calls }
      end

      ##
      # Makes a non-streaming request to the vendor API
      #
      # @param body [Hash] Request body
      # @return [Hash] Parsed response with normalized usage
      # @raise [APIError] on request failure
      # @private
      #
      def make_request(body)
        uri = URI("#{@api_base}/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        response = http.request(request)

        handle_api_error(response, provider_name) unless response.code.start_with?("2")

        result = RAAF::Utils.parse_json(response.body)

        if result["usage"]
          normalized_usage = RAAF::Usage::Normalizer.normalize(
            result,
            provider_name: self.class::USAGE_PROVIDER_KEY,
            model: result["model"] || body[:model]
          )
          result["usage"] = normalized_usage if normalized_usage
        end

        result
      end

      ##
      # Makes a streaming request to the vendor API
      #
      # @param body [Hash] Request body
      # @yield [String] Yields raw SSE lines
      # @private
      #
      def make_streaming_request(body)
        body[:stream] = true
        uri = URI("#{@api_base}/chat/completions")

        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{@api_key}"
          request["Content-Type"] = "application/json"
          request["Accept"] = "text/event-stream"
          request.body = body.to_json

          http.request(request) do |response|
            handle_api_error(response, provider_name) unless response.code.start_with?("2")

            response.read_body do |chunk|
              chunk.split("\n").each do |line|
                yield line if block_given?
              end
            end
          end
        end
      end

      ##
      # Handles vendor API errors with OpenAI-style error bodies
      #
      # @param response [HTTPResponse] API response
      # @param provider [String] Provider name
      # @raise [AuthenticationError] for 401 errors
      # @raise [RateLimitError] for 429 errors
      # @raise [APIError] for other 4xx errors
      # @private
      #
      def handle_api_error(response, provider)
        case response.code.to_i
        when 401
          raise AuthenticationError, "Invalid #{provider} API key"
        when 429
          retry_after = response["retry-after"] || response["x-ratelimit-reset"]
          raise RateLimitError, "#{provider} rate limit exceeded. Retry after: #{retry_after}"
        when 400
          begin
            error_data = JSON.parse(response.body)
            error_message = error_data.dig("error", "message") || response.body
          rescue StandardError
            error_message = response.body
          end
          raise APIError, "#{provider} API error: #{error_message}"
        else
          super
        end
      end
    end
  end
end
