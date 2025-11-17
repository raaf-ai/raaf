# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
# Interface is required from raaf-core gem

module RAAF
  module Models
    ##
    # Google Gemini model provider
    #
    # This provider implements the ModelInterface for Google's Gemini models,
    # translating between OpenAI's API format and Google's GenerativeAI API.
    # It supports Gemini 2.5, Gemini 2.0, Gemini 1.5, and Gemini 1.0 models.
    #
    # Features:
    # - Automatic format conversion between OpenAI and Gemini APIs
    # - Tool/function calling support
    # - System instruction handling
    # - Streaming support with Server-Sent Events
    # - Multimodal support (text and vision)
    #
    # @example Basic usage
    #   provider = GeminiProvider.new(api_key: "your-key")
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "gemini-2.0-flash-exp"
    #   )
    #
    # @example With tools
    #   provider = GeminiProvider.new
    #   response = provider.chat_completion(
    #     messages: messages,
    #     model: "gemini-1.5-pro-latest",
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
    class GeminiProvider < ModelInterface
      include RAAF::Logger

      # Default Gemini API endpoint
      DEFAULT_API_BASE = "https://generativelanguage.googleapis.com"

      # List of supported Gemini models
      SUPPORTED_MODELS = %w[
        gemini-2.5-pro
        gemini-2.5-flash
        gemini-2.5-flash-lite
        gemini-2.0-flash
        gemini-2.0-flash-exp
        gemini-2.0-flash-lite
        gemini-1.5-pro-latest
        gemini-1.5-flash-latest
        gemini-1.5-pro
        gemini-1.5-flash
        gemini-1.0-pro
      ].freeze

      # HTTP timeout accessor for Runner integration
      attr_accessor :http_timeout

      ##
      # Initialize a new Gemini provider
      #
      # @param api_key [String, nil] Gemini API key (defaults to GEMINI_API_KEY env var)
      # @param api_base [String, nil] API base URL (defaults to GEMINI_API_BASE env var or default)
      # @param timeout [Integer, nil] HTTP timeout in seconds (default: 120)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, timeout: nil, **options)
        @api_key = api_key || ENV.fetch("GEMINI_API_KEY", nil)
        @api_base = api_base || ENV["GEMINI_API_BASE"] || DEFAULT_API_BASE
        @http_timeout = timeout || ENV.fetch("GEMINI_HTTP_TIMEOUT", "120").to_i
        @options = options

        raise RAAF::AuthenticationError, "Gemini API key is required" if @api_key.nil? || @api_key.empty?
      end

      ##
      # Performs a chat completion using Gemini's GenerativeAI API
      #
      # Converts OpenAI-format messages to Gemini format, makes the API call,
      # and converts the response back to OpenAI format for compatibility.
      #
      # Supports automatic continuation when responses are truncated (MAX_TOKENS).
      # Uses Gemini's multi-turn conversation pattern by appending responses
      # to the conversation history and making additional API calls.
      #
      # @param messages [Array<Hash>] Conversation messages in OpenAI format
      # @param model [String] Gemini model to use
      # @param tools [Array<Hash>, nil] Tools/functions available to the model
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional parameters (max_tokens, temperature, auto_continuation, etc.)
      # @return [Hash] Response in OpenAI format
      # @raise [ModelNotFoundError] if model is not supported
      # @raise [APIError] if the API request fails
      #
      def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        validate_model(model)

        # Extract continuation parameters
        auto_continuation = kwargs.fetch(:auto_continuation, true)
        max_continuation_attempts = kwargs.fetch(:max_continuation_attempts, 10)

        # Initialize conversation history with provided messages
        conversation_messages = messages.dup
        accumulated_content = ""
        chunk_number = 0
        # Use OpenAI-compatible key names (input_tokens/output_tokens, not prompt_tokens/completion_tokens)
        total_usage = { input_tokens: 0, output_tokens: 0, total_tokens: 0 }

        loop do
          chunk_number += 1

          # Make single API call
          result = make_gemini_api_call(
            messages: conversation_messages,
            model: model,
            tools: tools,
            stream: stream,
            **kwargs
          )

          # Extract response data
          response_content = result.dig("choices", 0, "message", "content") || ""
          finish_reason = result.dig("choices", 0, "finish_reason")
          usage = result["usage"] || {}

          # Accumulate content and usage
          accumulated_content += response_content

          # Gemini API returns inputTokens/outputTokens - accumulate using OpenAI-compatible key names
          total_usage[:input_tokens] += usage["input_tokens"] || usage["inputTokens"] || usage["prompt_tokens"] || 0
          total_usage[:output_tokens] += usage["output_tokens"] || usage["outputTokens"] || usage["completion_tokens"] || 0
          total_usage[:total_tokens] += usage["total_tokens"] || usage["totalTokens"] || 0

          # Check if continuation is needed
          is_truncated = finish_reason == "length" # "length" is the OpenAI-compatible mapping for MAX_TOKENS
          response_complete = !is_truncated

          # Debug logging
          log_debug("🔍 Checking continuation need",
                    chunk: chunk_number,
                    finish_reason: finish_reason,
                    truncated: is_truncated,
                    content_length: accumulated_content.length)

          # Exit if response is complete
          if response_complete
            log_debug("✅ Response complete", total_chunks: chunk_number)
            break
          end

          # Check if auto-continuation is disabled
          unless auto_continuation
            log_warn("⚠️ Response truncated but auto_continuation=false")
            break
          end

          # Check if max attempts reached
          if chunk_number >= max_continuation_attempts
            log_warn("⚠️ Max continuation attempts reached", max_chunks: max_continuation_attempts)
            break
          end

          # Prepare for continuation: Add assistant's response to conversation history
          log_debug("🔄 Continuing conversation", attempt: chunk_number + 1, max_attempts: max_continuation_attempts)

          conversation_messages << {
            role: "assistant",
            content: response_content
          }

          # Add continuation prompt
          conversation_messages << {
            role: "user",
            content: "Continue from where you left off. Do not repeat what you already provided."
          }
        end

        # Return final accumulated response with canonical RAAF token field names
        # Usage::Normalizer can read both old (prompt_tokens) and canonical (input_tokens) formats
        # We return canonical format directly - no conversion needed
        normalized_usage = total_usage

        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => accumulated_content,
              "tool_calls" => nil
            }.compact,
            "finish_reason" => chunk_number >= max_continuation_attempts ? "length" : "stop"
          }],
          "usage" => normalized_usage,
          "model" => model,
          "continuation_chunks" => chunk_number
        }
      end

      ##
      # Responses API compatibility method - delegates to perform_chat_completion
      # Runner calls responses_completion(), so we need to implement it
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Gemini model to use
      # @param tools [Array<Hash>, nil] Available tools
      # @return [Hash] Standardized chat completion response
      #
      def responses_completion(messages:, model:, tools: nil, **kwargs)
        log_debug("🔍 responses_completion called")

        # Get Chat Completions format response
        chat_result = perform_chat_completion(messages: messages, model: model, tools: tools, **kwargs)

        log_debug("🔍 chat_result from perform_chat_completion",
                  has_choices: chat_result.key?("choices"),
                  has_usage: chat_result.key?("usage"),
                  usage_value: chat_result["usage"],
                  choices_count: chat_result["choices"]&.size)

        # Convert Chat Completions format to Responses API format
        # Chat Completions: { "choices" => [...], "usage" => {...}, "model" => ... }
        # Responses API: { "output" => [...], "usage" => {...}, "model" => ... }

        responses_result = {
          "output" => chat_result["choices"],  # Rename "choices" → "output"
          "usage" => chat_result["usage"],      # Keep usage unchanged
          "model" => chat_result["model"]       # Keep model unchanged
        }

        # Preserve continuation_chunks if present
        if chat_result["continuation_chunks"]
          responses_result["continuation_chunks"] = chat_result["continuation_chunks"]
        end

        log_debug("🔍 responses_completion final result",
                  has_output: responses_result.key?("output"),
                  has_usage: responses_result.key?("usage"),
                  usage_value: responses_result["usage"],
                  output_count: responses_result["output"]&.size)

        responses_result
      end

      ##
      # Streams a chat completion using Server-Sent Events
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Gemini model to use
      # @param tools [Array<Hash>, nil] Available tools
      # @yield [Hash] Yields streaming chunks with type, content, and accumulated data
      # @return [Hash] Final response with accumulated content
      #
      def perform_stream_completion(messages:, model:, tools: nil, **kwargs, &block)
        validate_model(model)

        endpoint = "streamGenerateContent"
        uri = URI("#{@api_base}/v1beta/models/#{model}:#{endpoint}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @http_timeout
        http.open_timeout = @http_timeout

        request = Net::HTTP::Post.new(uri)
        request["x-goog-api-key"] = @api_key
        request["Content-Type"] = "application/json"
        request["Accept"] = "text/event-stream"

        system_instruction, contents = extract_system_instruction(messages)

        body = {
          contents: contents
        }

        body[:systemInstruction] = { parts: [{ text: system_instruction }] } if system_instruction
        body[:tools] = convert_tools_to_gemini(tools) if tools

        generation_config = build_generation_config(kwargs)
        body[:generationConfig] = generation_config unless generation_config.empty?

        request.body = JSON.generate(body)

        accumulated_content = ""

        http.request(request) do |response|
          handle_api_error(response, "Gemini") unless response.is_a?(Net::HTTPSuccess)

          response.read_body do |chunk|
            process_gemini_stream_chunk(chunk, accumulated_content, &block)
          end
        end

        { content: accumulated_content, tool_calls: [] }
      end

      ##
      # Returns list of supported Gemini models
      #
      # @return [Array<String>] Supported model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "Gemini"
      #
      def provider_name
        "Gemini"
      end

      private

      ##
      # Makes a single Gemini API call without continuation logic
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model name
      # @param tools [Array<Hash>, nil] Tools
      # @param stream [Boolean] Streaming flag
      # @param kwargs [Hash] Additional parameters
      # @return [Hash] Response in OpenAI format
      # @private
      #
      def make_gemini_api_call(messages:, model:, tools: nil, stream: false, **kwargs)
        # Build API endpoint
        endpoint = stream ? "streamGenerateContent" : "generateContent"
        uri = URI("#{@api_base}/v1beta/models/#{model}:#{endpoint}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @http_timeout
        http.open_timeout = @http_timeout

        request = Net::HTTP::Post.new(uri)
        request["x-goog-api-key"] = @api_key
        request["Content-Type"] = "application/json"

        # Convert OpenAI format to Gemini format
        system_instruction, contents = extract_system_instruction(messages)

        body = {
          contents: contents
        }

        # Add system instruction if present
        body[:systemInstruction] = { parts: [{ text: system_instruction }] } if system_instruction

        # Add tools if present
        body[:tools] = convert_tools_to_gemini(tools) if tools

        # Add generation config
        generation_config = build_generation_config(kwargs)
        body[:generationConfig] = generation_config unless generation_config.empty?

        request.body = JSON.generate(body)

        response = http.request(request)

        handle_api_error(response, "Gemini") unless response.is_a?(Net::HTTPSuccess)

        result = RAAF::Utils.parse_json(response.body)
        convert_gemini_to_openai_format(result)
      end

      ##
      # Extracts system instruction from OpenAI format messages
      #
      # Gemini uses a separate systemInstruction parameter rather than system role messages.
      # This method separates system messages from user/assistant messages.
      #
      # @param messages [Array<Hash>] Messages in OpenAI format
      # @return [Array(String, Array<Hash>)] System instruction and contents array
      # @private
      #
      def extract_system_instruction(messages)
        system_instruction = nil
        contents = []

        messages.each do |message|
          if message[:role] == "system"
            system_instruction = message[:content]
          else
            # Convert OpenAI role to Gemini role
            gemini_role = message[:role] == "assistant" ? "model" : "user"
            contents << {
              role: gemini_role,
              parts: [{ text: message[:content] }]
            }
          end
        end

        [system_instruction, contents]
      end

      ##
      # Converts OpenAI tool format to Gemini function declarations
      #
      # @param tools [Array<Hash>, nil] Tools in OpenAI format
      # @return [Array<Hash>] Tools in Gemini format
      # @private
      #
      def convert_tools_to_gemini(tools)
        return [] unless tools

        [{
          functionDeclarations: tools.map do |tool|
            if tool.is_a?(Hash) && tool[:type] == "function"
              {
                name: tool.dig(:function, :name),
                description: tool.dig(:function, :description),
                parameters: tool.dig(:function, :parameters) || {}
              }
            else
              tool
            end
          end
        }]
      end

      ##
      # Builds generation config from kwargs
      #
      # @param kwargs [Hash] Additional parameters
      # @return [Hash] Generation config for Gemini API
      # @private
      #
      def build_generation_config(kwargs)
        config = {}

        config[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        config[:topP] = kwargs[:top_p] if kwargs[:top_p]
        config[:topK] = kwargs[:top_k] if kwargs[:top_k]
        config[:maxOutputTokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        config[:stopSequences] = kwargs[:stop] if kwargs[:stop]

        # JSON schema support for structured outputs
        # Gemini supports responseMimeType and responseSchema parameters
        if kwargs[:response_format]
          response_format = kwargs[:response_format]
          if response_format[:type] == "json_schema" && response_format[:json_schema]
            config[:responseMimeType] = "application/json"
            # Extract the schema from RAAF's response_format structure
            # Filter out additionalProperties for Gemini compatibility
            schema = response_format[:json_schema][:schema]
            config[:responseSchema] = filter_additional_properties(schema)
          end
        end

        config
      end

      ##
      # Recursively filters out additionalProperties fields from schema
      #
      # Gemini's API doesn't support the additionalProperties field that
      # OpenAI requires for strict schemas. This method removes all
      # additionalProperties keys while preserving all other schema fields.
      #
      # @param schema [Hash, Array, Object] Schema structure to filter
      # @return [Hash, Array, Object] Filtered schema without additionalProperties
      # @private
      #
      def filter_additional_properties(schema)
        return schema unless schema.is_a?(Hash)

        # Remove additionalProperties from current level (handle both string and symbol keys)
        filtered = schema.reject { |k, _| k == "additionalProperties" || k == :additionalProperties }

        # Recursively filter nested structures
        filtered.transform_values do |value|
          case value
          when Hash
            filter_additional_properties(value)
          when Array
            value.map { |item| filter_additional_properties(item) }
          else
            value
          end
        end
      end

      ##
      # Converts Gemini API response to OpenAI format
      #
      # @param result [Hash] Gemini API response
      # @return [Hash] Response in OpenAI format
      # @private
      #
      def convert_gemini_to_openai_format(result)
        candidate = result["candidates"]&.first || {}
        content_part = candidate.dig("content", "parts")&.first || {}

        # Extract text content
        content = content_part["text"] || ""

        # Extract tool calls if present
        tool_calls = extract_tool_calls(content_part)

        # Map finish reason
        finish_reason = map_finish_reason(candidate["finishReason"])

        # Extract usage metadata
        usage = extract_usage_metadata(result["usageMetadata"])

        response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => content,
              "tool_calls" => tool_calls
            }.compact,
            "finish_reason" => finish_reason
          }],
          "usage" => usage,
          "model" => result["modelVersion"] || result["model"]
        }

        # NOTE: extract_usage_metadata returns canonical RAAF format
        # {"input_tokens" => X, "output_tokens" => Y, "total_tokens" => Z}
        # This matches Usage::Normalizer's expected output format

        response
      end

      ##
      # Extracts tool calls from Gemini response part
      #
      # @param part [Hash] Content part from Gemini response
      # @return [Array<Hash>, nil] Tool calls in OpenAI format
      # @private
      #
      def extract_tool_calls(part)
        function_call = part["functionCall"]
        return nil unless function_call

        [{
          id: "call_#{SecureRandom.hex(12)}",
          type: "function",
          function: {
            name: function_call["name"],
            arguments: JSON.generate(function_call["args"] || {})
          }
        }]
      end

      ##
      # Maps Gemini finish reason to OpenAI format
      #
      # @param gemini_reason [String] Gemini finish reason
      # @return [String] OpenAI finish reason
      # @private
      #
      def map_finish_reason(gemini_reason)
        case gemini_reason
        when "STOP" then "stop"
        when "MAX_TOKENS" then "length"
        when "SAFETY" then "content_filter"
        when "RECITATION" then "content_filter"
        else "stop"
        end
      end

      ##
      # Extracts usage metadata and converts to canonical RAAF format
      #
      # @param metadata [Hash] Gemini usage metadata
      # @return [Hash] Usage in canonical format (input_tokens, output_tokens, total_tokens)
      # @private
      #
      def extract_usage_metadata(metadata)
        return {} unless metadata

        {
          "input_tokens" => metadata["promptTokenCount"] || 0,
          "output_tokens" => metadata["candidatesTokenCount"] || 0,
          "total_tokens" => metadata["totalTokenCount"] || 0
        }
      end

      ##
      # Processes a streaming chunk from Gemini's SSE response
      #
      # @param chunk [String] Raw SSE chunk
      # @param accumulated_content [String] Content accumulated so far
      # @yield [Hash] Yields processed chunk data
      # @private
      #
      def process_gemini_stream_chunk(chunk, accumulated_content)
        # Gemini streaming returns JSON objects, not SSE format
        # Each chunk is a complete JSON response
        return if chunk.strip.empty?

        begin
          json_data = RAAF::Utils.parse_json(chunk)

          candidate = json_data["candidates"]&.first
          return unless candidate

          content_part = candidate.dig("content", "parts")&.first
          return unless content_part

          delta = content_part["text"]
          if delta
            accumulated_content << delta
            if block_given?
              yield({
                type: "content",
                content: delta,
                accumulated_content: accumulated_content
              })
            end
          end

          # Check for finish
          if candidate["finishReason"]
            if block_given?
              yield({
                type: "finish",
                finish_reason: map_finish_reason(candidate["finishReason"]),
                accumulated_content: accumulated_content,
                accumulated_tool_calls: []
              })
            end
          end
        rescue JSON::ParserError
          # Skip malformed chunks
          nil
        end
      end
    end
  end
end
