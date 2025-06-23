# frozen_string_literal: true

require "json"
require_relative "interface"
require_relative "retryable_provider"
require_relative "../http_client"

module OpenAIAgents
  module Models
    # Cohere API provider implementation
    #
    # This provider supports Cohere's Command R models for chat completion.
    # Includes support for tools (function calling) and streaming.
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
    #     model: "command-r",
    #     tools: [weather_tool]
    #   )
    class CohereProvider < ModelInterface
      include RetryableProvider
      
      API_BASE = "https://api.cohere.com/v2"
      
      SUPPORTED_MODELS = %w[
        command-r-plus-08-2024
        command-r-plus
        command-r-08-2024
        command-r
        command-r7b-12-2024
      ].freeze
      
      # Role mapping from OpenAI format to Cohere format
      ROLE_MAPPING = {
        "system" => "system",
        "user" => "user",
        "assistant" => "assistant",
        "tool" => "tool"
      }.freeze

      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_key ||= ENV["COHERE_API_KEY"]
        @api_base ||= api_base || API_BASE
        @http_client = HTTPClient.new(default_headers: {
          "Authorization" => "Bearer #{@api_key}",
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "X-Client-Name" => "openai-agents-ruby"
        })
      end

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
        if tools && !tools.empty?
          body[:tools] = convert_tools(tools)
        end
        
        # Add optional parameters
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:p] = kwargs[:top_p] if kwargs[:top_p]
        body[:k] = kwargs[:top_k] if kwargs[:top_k]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:seed] = kwargs[:seed] if kwargs[:seed]
        
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
        if tools && !tools.empty?
          body[:tools] = convert_tools(tools)
        end
        
        # Add optional parameters from kwargs
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:p] = kwargs[:top_p] if kwargs[:top_p]
        body[:k] = kwargs[:top_k] if kwargs[:top_k]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:seed] = kwargs[:seed] if kwargs[:seed]
        
        with_retry("stream_completion") do
          @http_client.post_stream("#{@api_base}/chat", body: body) do |chunk|
            # Parse SSE chunk and convert to OpenAI format
            if chunk.start_with?("data: ")
              data = chunk[6..-1].strip
              unless data == "[DONE]"
                begin
                  parsed = JSON.parse(data)
                  yield convert_stream_chunk(parsed) if block_given?
                rescue JSON::ParserError => e
                  # Log parse error but continue
                  puts "[CohereProvider] Failed to parse stream chunk: #{e.message}"
                end
              end
            end
          end
        end
      end

      def supported_models
        SUPPORTED_MODELS
      end

      def provider_name
        "Cohere"
      end

      private

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
            "usage" => cohere_chunk["usage"] ? {
              "prompt_tokens" => cohere_chunk["usage"]["billed_units"]["input_tokens"] || 0,
              "completion_tokens" => cohere_chunk["usage"]["billed_units"]["output_tokens"] || 0,
              "total_tokens" => (cohere_chunk["usage"]["billed_units"]["input_tokens"] || 0) + 
                              (cohere_chunk["usage"]["billed_units"]["output_tokens"] || 0)
            } : nil
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