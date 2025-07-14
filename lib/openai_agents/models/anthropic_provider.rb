# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "interface"

module OpenAIAgents
  module Models
    ##
    # Anthropic Claude model provider
    #
    # This provider implements the ModelInterface for Anthropic's Claude models,
    # translating between OpenAI's API format and Anthropic's Messages API.
    # It supports all Claude 3 models including Opus, Sonnet, and Haiku variants.
    #
    # Features:
    # - Automatic format conversion between OpenAI and Anthropic APIs
    # - Streaming support with Server-Sent Events
    # - Tool/function calling support
    # - System message handling
    # - JSON schema response format (via system prompts)
    #
    # @example Basic usage
    #   provider = AnthropicProvider.new(api_key: "your-key")
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "claude-3-5-sonnet-20241022"
    #   )
    #
    # @example With tools
    #   provider = AnthropicProvider.new
    #   response = provider.chat_completion(
    #     messages: messages,
    #     model: "claude-3-opus-20240229",
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
    class AnthropicProvider < ModelInterface
      # Default Anthropic API endpoint
      DEFAULT_API_BASE = "https://api.anthropic.com"

      # List of supported Claude models
      # Includes latest Claude 3.5 and Claude 3 models
      SUPPORTED_MODELS = %w[
        claude-3-5-sonnet-20241022 claude-3-5-haiku-20241022
        claude-3-opus-20240229 claude-3-sonnet-20240229 claude-3-haiku-20240307
      ].freeze

      ##
      # Initialize a new Anthropic provider
      #
      # @param api_key [String, nil] Anthropic API key (defaults to ANTHROPIC_API_KEY env var)
      # @param api_base [String, nil] API base URL (defaults to ANTHROPIC_API_BASE env var or default)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      # rubocop:disable Lint/MissingSuper
      def initialize(api_key: nil, api_base: nil, **options)
        @api_key = api_key || ENV.fetch("ANTHROPIC_API_KEY", nil)
        @api_base = api_base || ENV["ANTHROPIC_API_BASE"] || DEFAULT_API_BASE
        @options = options

        raise AuthenticationError, "Anthropic API key is required" unless @api_key
      end
      # rubocop:enable Lint/MissingSuper

      ##
      # Performs a chat completion using Anthropic's Messages API
      #
      # Converts OpenAI-format messages to Anthropic format, makes the API call,
      # and converts the response back to OpenAI format for compatibility.
      #
      # @param messages [Array<Hash>] Conversation messages in OpenAI format
      # @param model [String] Claude model to use
      # @param tools [Array<Hash>, nil] Tools/functions available to the model
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional parameters (max_tokens, response_format, etc.)
      # @return [Hash] Response in OpenAI format
      # @raise [ModelNotFoundError] if model is not supported
      # @raise [APIError] if the API request fails
      #
      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        validate_model(model)

        uri = URI("#{@api_base}/v1/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["x-api-key"] = @api_key
        request["Content-Type"] = "application/json"
        request["anthropic-version"] = "2023-06-01"

        # Convert OpenAI format to Anthropic format
        system_message, user_messages = extract_system_message(messages)

        body = {
          model: model,
          messages: user_messages,
          max_tokens: kwargs[:max_tokens] || 1024,
          stream: stream
        }
        body[:system] = system_message if system_message
        body[:tools] = convert_tools_to_anthropic(tools) if tools

        # Add response_format support - Anthropic doesn't support JSON schema directly
        # but we can enhance the system message for structured output
        if kwargs[:response_format] && kwargs[:response_format][:type] == "json_schema"
          # rubocop:disable Layout/LineLength
          json_instruction = "\n\nIMPORTANT: Please respond with valid JSON only. Do not include any other text or explanation."
          # rubocop:enable Layout/LineLength
          if kwargs[:response_format][:json_schema] && kwargs[:response_format][:json_schema][:schema]
            schema = kwargs[:response_format][:json_schema][:schema]
            json_instruction += " Follow this JSON schema: #{schema.to_json}"
          end
          body[:system] = (body[:system] || "") + json_instruction
        end

        request.body = JSON.generate(body)

        response = http.request(request)

        handle_api_error(response, "Anthropic") unless response.is_a?(Net::HTTPSuccess)

        result = JSON.parse(response.body)
        convert_anthropic_to_openai_format(result)
      end

      ##
      # Streams a chat completion using Server-Sent Events
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Claude model to use
      # @param tools [Array<Hash>, nil] Available tools
      # @yield [Hash] Yields streaming chunks with type, content, and accumulated data
      # @return [Hash] Final response with accumulated content
      #
      def stream_completion(messages:, model:, tools: nil, &block)
        validate_model(model)

        uri = URI("#{@api_base}/v1/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["x-api-key"] = @api_key
        request["Content-Type"] = "application/json"
        request["anthropic-version"] = "2023-06-01"
        request["Accept"] = "text/event-stream"

        system_message, user_messages = extract_system_message(messages)

        body = {
          model: model,
          messages: user_messages,
          max_tokens: 1024,
          stream: true
        }
        body[:system] = system_message if system_message
        body[:tools] = convert_tools_to_anthropic(tools) if tools

        # Add response_format support for streaming
        if kwargs[:response_format] && kwargs[:response_format][:type] == "json_schema"
          # rubocop:disable Layout/LineLength
          json_instruction = "\n\nIMPORTANT: Please respond with valid JSON only. Do not include any other text or explanation."
          # rubocop:enable Layout/LineLength
          if kwargs[:response_format][:json_schema] && kwargs[:response_format][:json_schema][:schema]
            schema = kwargs[:response_format][:json_schema][:schema]
            json_instruction += " Follow this JSON schema: #{schema.to_json}"
          end
          body[:system] = (body[:system] || "") + json_instruction
        end

        request.body = JSON.generate(body)

        accumulated_content = ""

        http.request(request) do |response|
          handle_api_error(response, "Anthropic") unless response.is_a?(Net::HTTPSuccess)

          response.read_body do |chunk|
            process_anthropic_stream_chunk(chunk, accumulated_content, &block)
          end
        end

        { content: accumulated_content, tool_calls: [] }
      end

      ##
      # Returns list of supported Claude models
      #
      # @return [Array<String>] Supported model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "Anthropic"
      #
      def provider_name
        "Anthropic"
      end

      private

      ##
      # Extracts system message from OpenAI format messages
      #
      # Anthropic uses a separate system parameter rather than system role messages.
      # This method separates system messages from user/assistant messages.
      #
      # @param messages [Array<Hash>] Messages in OpenAI format
      # @return [Array(String, Array<Hash>)] System message and remaining messages
      # @private
      #
      def extract_system_message(messages)
        system_message = nil
        user_messages = []

        messages.each do |message|
          if message[:role] == "system"
            system_message = message[:content]
          else
            user_messages << message
          end
        end

        [system_message, user_messages]
      end

      ##
      # Converts OpenAI tool format to Anthropic tool format
      #
      # @param tools [Array<Hash>, nil] Tools in OpenAI format
      # @return [Array<Hash>] Tools in Anthropic format
      # @private
      #
      def convert_tools_to_anthropic(tools)
        return [] unless tools

        tools.map do |tool|
          if tool.is_a?(Hash) && tool[:type] == "function"
            {
              name: tool.dig(:function, :name),
              description: tool.dig(:function, :description),
              input_schema: tool.dig(:function, :parameters) || {}
            }
          else
            tool
          end
        end
      end

      ##
      # Converts Anthropic API response to OpenAI format
      #
      # @param result [Hash] Anthropic API response
      # @return [Hash] Response in OpenAI format
      # @private
      #
      def convert_anthropic_to_openai_format(result)
        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => result["content"]&.first&.dig("text") || ""
            },
            "finish_reason" => result["stop_reason"]
          }],
          "usage" => result["usage"],
          "model" => result["model"]
        }
      end

      ##
      # Processes a streaming chunk from Anthropic's SSE response
      #
      # @param chunk [String] Raw SSE chunk
      # @param accumulated_content [String] Content accumulated so far
      # @yield [Hash] Yields processed chunk data
      # @private
      #
      def process_anthropic_stream_chunk(chunk, accumulated_content)
        chunk.split("\n").each do |line|
          next unless line.start_with?("data: ")

          data = line[6..].strip
          next if data.empty?

          begin
            json_data = JSON.parse(data)

            if json_data["type"] == "content_block_delta"
              delta = json_data.dig("delta", "text")
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
            elsif json_data["type"] == "message_stop"
              if block_given?
                yield({
                  type: "finish",
                  finish_reason: "stop",
                  accumulated_content: accumulated_content,
                  accumulated_tool_calls: []
                })
              end
            end
          rescue JSON::ParserError
            next
          end
        end
      end
    end
  end
end
