# frozen_string_literal: true

require "json"
require_relative "interface"
require_relative "retryable_provider"
require_relative "../http_client"

module OpenAIAgents
  module Models
    ##
    # Cohere API provider implementation
    #
    # This provider supports Cohere's Command R models for chat completion.
    # Command R models are optimized for conversational AI and RAG (Retrieval-Augmented Generation)
    # applications. The provider translates between OpenAI's API format and Cohere's v2 Chat API.
    #
    # Features:
    # - Support for Command R and Command R+ models
    # - Tool/function calling capabilities
    # - Streaming responses
    # - System message support
    # - JSON response format
    # - Automatic format conversion between APIs
    #
    # @example Basic usage
    #   provider = CohereProvider.new(api_key: ENV["COHERE_API_KEY"])
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "command-r"
    #   )
    #
    # @example With tools
    #   provider.chat_completion(
    #     messages: messages,
    #     model: "command-r-plus",
    #     tools: [weather_tool, search_tool]
    #   )
    #
    # @example With streaming
    #   provider.stream_completion(
    #     messages: messages,
    #     model: "command-r-08-2024"
    #   ) do |chunk|
    #     print chunk["choices"][0]["delta"]["content"]
    #   end
    #
    class CohereProvider < ModelInterface
      include RetryableProvider

      # Cohere API v2 base URL
      API_BASE = "https://api.cohere.com/v2"

      # Supported Command R model variants
      # Includes both standard and plus versions with different capabilities
      SUPPORTED_MODELS = %w[
        command-r-plus-08-2024
        command-r-plus
        command-r-08-2024
        command-r
        command-r7b-12-2024
      ].freeze

      # Role mapping from OpenAI format to Cohere format
      # Cohere uses similar roles but with specific handling for tool messages
      ROLE_MAPPING = {
        "system" => "system",
        "user" => "user",
        "assistant" => "assistant",
        "tool" => "tool"
      }.freeze

      ##
      # Initialize a new Cohere provider
      #
      # @param api_key [String, nil] Cohere API key (defaults to COHERE_API_KEY env var)
      # @param api_base [String, nil] API base URL (defaults to Cohere v2 endpoint)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_key ||= ENV.fetch("COHERE_API_KEY", nil)
        @api_base ||= api_base || API_BASE
        @http_client = HTTPClient.new(default_headers: {
                                        "Authorization" => "Bearer #{@api_key}",
                                        "Content-Type" => "application/json",
                                        "Accept" => "application/json",
                                        "X-Client-Name" => "openai-agents-ruby"
                                      })
      end

      ##
      # Performs a chat completion using Cohere's v2 Chat API
      #
      # Converts OpenAI-format messages to Cohere format, makes the API call,
      # and converts the response back to OpenAI format for compatibility.
      #
      # @param messages [Array<Hash>] Conversation messages in OpenAI format
      # @param model [String] Cohere model to use
      # @param tools [Array<Hash>, nil] Tools/functions available to the model
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional parameters (temperature, max_tokens, etc.)
      # @option kwargs [Float] :temperature (0.0-1.0) Randomness in generation
      # @option kwargs [Integer] :max_tokens Maximum tokens to generate
      # @option kwargs [Float] :top_p Nucleus sampling parameter
      # @option kwargs [Integer] :top_k Top-k sampling parameter
      # @option kwargs [Hash] :response_format Response format specification
      # @return [Hash] Response in OpenAI format
      # @raise [ModelNotFoundError] if model is not supported
      # @raise [APIError] if the API request fails
      #
      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        validate_model(model)

        # Convert messages to Cohere format
        cohere_messages, system_prompt = convert_messages(messages)

        body = {
          model: model,
          messages: cohere_messages
        }

        # Add system prompt if present
        body[:system] = system_prompt if system_prompt

        # Add tools if provided
        body[:tools] = convert_tools(tools) if tools && !tools.empty?

        # Add optional parameters
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:p] = kwargs[:top_p] if kwargs[:top_p]
        body[:k] = kwargs[:top_k] if kwargs[:top_k]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:seed] = kwargs[:seed] if kwargs[:seed]

        # Add response_format support - Cohere doesn't support JSON schema directly
        # but we can use JSON response format for structured output
        if kwargs[:response_format] && kwargs[:response_format][:type] == "json_schema"
          # Enable JSON response format
          body[:response_format] = { type: "json_object" }

          # Enhance system prompt with JSON schema instructions
          if kwargs[:response_format][:json_schema] && kwargs[:response_format][:json_schema][:schema]
            schema = kwargs[:response_format][:json_schema][:schema]
            json_instruction = "\n\nIMPORTANT: Respond with valid JSON only. Follow this schema: #{schema.to_json}"
            body[:system] = (body[:system] || "") + json_instruction
          end
        elsif kwargs[:response_format]
          # Pass through other response formats
          body[:response_format] = kwargs[:response_format]
        end

        if stream
          stream_completion(messages: messages, model: model, tools: tools, **kwargs)
        else
          with_retry("chat_completion") do
            response = @http_client.post("#{@api_base}/chat", body: body)

            if response.success?
              convert_response(response.parsed_body)
            else
              handle_api_error(response, "Cohere")
            end
          end
        end
      end

      ##
      # Streams a chat completion using Server-Sent Events
      #
      # Processes streaming responses from Cohere and yields them in OpenAI format.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Cohere model to use
      # @param tools [Array<Hash>, nil] Available tools
      # @param kwargs [Hash] Additional parameters
      # @yield [Hash] Yields streaming chunks in OpenAI format
      # @return [void]
      #
      def stream_completion(messages:, model:, tools: nil, **kwargs)
        validate_model(model)

        # Convert messages to Cohere format
        cohere_messages, system_prompt = convert_messages(messages)

        body = {
          model: model,
          messages: cohere_messages,
          stream: true
        }

        # Add system prompt if present
        body[:system] = system_prompt if system_prompt

        # Add tools if provided
        body[:tools] = convert_tools(tools) if tools && !tools.empty?

        # Add optional parameters from kwargs
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:p] = kwargs[:top_p] if kwargs[:top_p]
        body[:k] = kwargs[:top_k] if kwargs[:top_k]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:seed] = kwargs[:seed] if kwargs[:seed]

        # Add response_format support for streaming
        if kwargs[:response_format] && kwargs[:response_format][:type] == "json_schema"
          # Enable JSON response format
          body[:response_format] = { type: "json_object" }

          # Enhance system prompt with JSON schema instructions
          if kwargs[:response_format][:json_schema] && kwargs[:response_format][:json_schema][:schema]
            schema = kwargs[:response_format][:json_schema][:schema]
            json_instruction = "\n\nIMPORTANT: Respond with valid JSON only. Follow this schema: #{schema.to_json}"
            body[:system] = (body[:system] || "") + json_instruction
          end
        elsif kwargs[:response_format]
          # Pass through other response formats
          body[:response_format] = kwargs[:response_format]
        end

        with_retry("stream_completion") do
          @http_client.post_stream("#{@api_base}/chat", body: body) do |chunk|
            # Parse SSE chunk and convert to OpenAI format
            if chunk.start_with?("data: ")
              data = chunk[6..].strip
              unless data == "[DONE]"
                begin
                  parsed = JSON.parse(data)
                  yield convert_stream_chunk(parsed) if block_given?
                rescue JSON::ParserError => e
                  # Log parse error but continue
                  log_debug("Failed to parse stream chunk: #{e.message}", provider: "CohereProvider",
                                                                          error_class: e.class.name)
                end
              end
            end
          end
        end
      end

      ##
      # Returns list of supported Cohere models
      #
      # @return [Array<String>] Supported model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "Cohere"
      #
      def provider_name
        "Cohere"
      end

      private

      ##
      # Converts OpenAI format messages to Cohere format
      #
      # Separates system messages and converts chat messages to Cohere's expected format.
      # System messages are combined into a single system prompt.
      #
      # @param messages [Array<Hash>] Messages in OpenAI format
      # @return [Array(Array<Hash>, String)] Cohere messages and system prompt
      # @private
      #
      def convert_messages(messages)
        system_messages = []
        chat_messages = []

        messages.each do |msg|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]

          case role
          when "system"
            system_messages << content
          when "user", "assistant"
            chat_messages << {
              role: ROLE_MAPPING[role],
              content: content
            }
          when "tool"
            # Convert tool response to Cohere format
            tool_call_id = msg[:tool_call_id] || msg["tool_call_id"]
            chat_messages << {
              role: "tool",
              tool_call_id: tool_call_id,
              content: content
            }
          end
        end

        # Combine system messages if multiple
        system_prompt = system_messages.join("\n\n") unless system_messages.empty?

        [chat_messages, system_prompt]
      end

      ##
      # Converts OpenAI tool format to Cohere tool format
      #
      # @param tools [Array<Hash>] Tools in OpenAI format
      # @return [Array<Hash>] Tools in Cohere format
      # @private
      #
      def convert_tools(tools)
        tools.map do |tool|
          tool_def = prepare_tools([tool]).first

          {
            type: "function",
            function: {
              name: tool_def[:function][:name],
              description: tool_def[:function][:description],
              parameters: tool_def[:function][:parameters]
            }
          }
        end
      end

      ##
      # Converts Cohere API response to OpenAI format
      #
      # Transforms Cohere's response structure to match OpenAI's expected format,
      # including handling of tool calls and usage statistics.
      #
      # @param cohere_response [Hash] Cohere API response
      # @return [Hash] Response in OpenAI format
      # @private
      #
      def convert_response(cohere_response)
        # Extract the message content
        message = cohere_response["message"]

        # Build OpenAI-compatible response
        response = {
          "id" => cohere_response["id"] || "chat-#{SecureRandom.hex(12)}",
          "object" => "chat.completion",
          "created" => Time.now.to_i,
          "model" => cohere_response["model"],
          "choices" => [{
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => message["content"] || ""
            },
            "finish_reason" => map_finish_reason(cohere_response["finish_reason"])
          }]
        }

        # Add tool calls if present
        if message["tool_calls"]
          response["choices"][0]["message"]["tool_calls"] = convert_tool_calls(message["tool_calls"])
        end

        # Add usage information if available
        if cohere_response["usage"]
          response["usage"] = {
            "prompt_tokens" => cohere_response["usage"]["billed_units"]["input_tokens"] || 0,
            "completion_tokens" => cohere_response["usage"]["billed_units"]["output_tokens"] || 0,
            "total_tokens" => (cohere_response["usage"]["billed_units"]["input_tokens"] || 0) +
                              (cohere_response["usage"]["billed_units"]["output_tokens"] || 0)
          }
        end

        response
      end

      ##
      # Converts Cohere streaming chunk to OpenAI format
      #
      # Maps different Cohere stream event types to OpenAI's streaming format.
      # Handles content deltas, tool calls, and completion events.
      #
      # @param cohere_chunk [Hash] Cohere streaming chunk
      # @return [Hash] Chunk in OpenAI streaming format
      # @private
      #
      def convert_stream_chunk(cohere_chunk)
        # Map Cohere stream events to OpenAI format
        case cohere_chunk["type"]
        when "message-start"
          {
            "id" => cohere_chunk["id"],
            "object" => "chat.completion.chunk",
            "created" => Time.now.to_i,
            "model" => cohere_chunk["model"],
            "choices" => [{
              "index" => 0,
              "delta" => { "role" => "assistant" },
              "finish_reason" => nil
            }]
          }
        when "content-delta"
          {
            "id" => cohere_chunk["id"],
            "object" => "chat.completion.chunk",
            "created" => Time.now.to_i,
            "model" => cohere_chunk["model"],
            "choices" => [{
              "index" => 0,
              "delta" => { "content" => cohere_chunk["delta"]["message"]["content"] },
              "finish_reason" => nil
            }]
          }
        when "tool-call-start"
          {
            "id" => cohere_chunk["id"],
            "object" => "chat.completion.chunk",
            "created" => Time.now.to_i,
            "model" => cohere_chunk["model"],
            "choices" => [{
              "index" => 0,
              "delta" => {
                "tool_calls" => [{
                  "id" => cohere_chunk["delta"]["message"]["tool_calls"]["id"],
                  "type" => "function",
                  "function" => {
                    "name" => cohere_chunk["delta"]["message"]["tool_calls"]["function"]["name"],
                    "arguments" => ""
                  }
                }]
              },
              "finish_reason" => nil
            }]
          }
        when "tool-call-delta"
          {
            "id" => cohere_chunk["id"],
            "object" => "chat.completion.chunk",
            "created" => Time.now.to_i,
            "model" => cohere_chunk["model"],
            "choices" => [{
              "index" => 0,
              "delta" => {
                "tool_calls" => [{
                  "function" => {
                    "arguments" => cohere_chunk["delta"]["message"]["tool_calls"]["function"]["arguments"]
                  }
                }]
              },
              "finish_reason" => nil
            }]
          }
        when "message-end"
          {
            "id" => cohere_chunk["id"],
            "object" => "chat.completion.chunk",
            "created" => Time.now.to_i,
            "model" => cohere_chunk["model"],
            "choices" => [{
              "index" => 0,
              "delta" => {},
              "finish_reason" => map_finish_reason(cohere_chunk["finish_reason"])
            }],
            "usage" => if cohere_chunk["usage"]
                         {
                           "prompt_tokens" => cohere_chunk["usage"]["billed_units"]["input_tokens"] || 0,
                           "completion_tokens" => cohere_chunk["usage"]["billed_units"]["output_tokens"] || 0,
                           "total_tokens" => (cohere_chunk["usage"]["billed_units"]["input_tokens"] || 0) +
                             (cohere_chunk["usage"]["billed_units"]["output_tokens"] || 0)
                         }
                       end
          }
        else
          # Unknown event type, return minimal chunk
          {
            "id" => cohere_chunk["id"] || "chunk-#{SecureRandom.hex(6)}",
            "object" => "chat.completion.chunk",
            "created" => Time.now.to_i,
            "model" => cohere_chunk["model"] || "unknown",
            "choices" => [{
              "index" => 0,
              "delta" => {},
              "finish_reason" => nil
            }]
          }
        end
      end

      ##
      # Converts Cohere tool calls to OpenAI format
      #
      # @param cohere_tool_calls [Array<Hash>] Tool calls from Cohere
      # @return [Array<Hash>] Tool calls in OpenAI format
      # @private
      #
      def convert_tool_calls(cohere_tool_calls)
        cohere_tool_calls.map do |call|
          {
            "id" => call["id"],
            "type" => "function",
            "function" => {
              "name" => call["function"]["name"],
              "arguments" => call["function"]["arguments"]
            }
          }
        end
      end

      ##
      # Maps Cohere finish reasons to OpenAI finish reasons
      #
      # @param cohere_reason [String] Cohere's finish reason
      # @return [String] OpenAI-compatible finish reason
      # @private
      #
      def map_finish_reason(cohere_reason)
        case cohere_reason
        when "complete"
          "stop"
        when "max_tokens"
          "length"
        when "tool_call"
          "tool_calls"
        else
          cohere_reason
        end
      end
    end
  end
end
