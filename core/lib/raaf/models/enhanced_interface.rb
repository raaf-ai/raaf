# frozen_string_literal: true

require_relative "interface"

module RAAF
  module Models
    ##
    # Enhanced Model Interface with Universal Handoff Support
    #
    # This enhanced interface extends the base ModelInterface to provide
    # universal handoff support across all provider implementations.
    # It includes default implementations that work with any provider
    # that supports function calling.
    #
    # @example Enhanced provider implementation
    #   class MyProvider < EnhancedModelInterface
    #     def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
    #       # Your implementation here
    #       # Handoff support is automatically available!
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
    class EnhancedModelInterface < ModelInterface

      ##
      # Default implementation of responses_completion
      #
      # This method provides automatic Responses API compatibility for any
      # provider that implements chat_completion. It converts between the
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
      # @example With input items for conversation continuation
      #   response = provider.responses_completion(
      #     messages: [{ role: "user", content: "Hello" }],
      #     model: "gpt-4",
      #     input: [
      #       { type: "message", role: "user", content: "Follow up" },
      #       { type: "function_call_output", call_id: "call_123", output: "Success" }
      #     ]
      #   )
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
      def responses_completion(messages:, model:, tools: nil, stream: false, previous_response_id: nil, input: nil, **kwargs)
        log_debug("🔧 ENHANCED INTERFACE: Converting chat_completion to responses_completion",
                  provider: provider_name,
                  has_tools: !tools.nil?,
                  tools_count: tools&.size || 0)

        # Convert input items back to messages if needed
        actual_messages = if input && input.any?
          convert_input_to_messages(input, messages)
        else
          messages
        end

        # Call the provider's chat_completion method
        response = chat_completion(
          messages: actual_messages,
          model: model,
          tools: tools,
          stream: stream,
          **kwargs
        )

        # Convert response to Responses API format
        convert_chat_to_responses_format(response)
      end

      ##
      # Check if provider supports handoffs
      #
      # By default, handoff support is available if the provider supports
      # function calling (i.e., accepts tools parameter).
      #
      # @example Checking handoff support
      #   provider = MyProvider.new
      #   if provider.supports_handoffs?
      #     puts "Handoffs are supported!"
      #   else
      #     puts "Use content-based handoff fallback"
      #   end
      #
      # @return [Boolean] True if handoffs are supported, false otherwise
      #
      def supports_handoffs?
        supports_function_calling?
      end

      ##
      # Check if provider supports function calling
      #
      # This method inspects the chat_completion method signature to determine
      # if it accepts a tools parameter, which indicates function calling support.
      #
      # @example Checking function calling support
      #   provider = MyProvider.new
      #   if provider.supports_function_calling?
      #     puts "Provider supports function calling"
      #   else
      #     puts "Provider is text-only"
      #   end
      #
      # @return [Boolean] True if function calling is supported, false otherwise
      #
      def supports_function_calling?
        method(:chat_completion).parameters.any? { |param| param[1] == :tools }
      end

      ##
      # Get provider capabilities
      #
      # Returns a comprehensive hash of provider capabilities including
      # API support, streaming, function calling, and handoff support.
      #
      # @example Getting provider capabilities
      #   provider = MyProvider.new
      #   caps = provider.capabilities
      #   puts "Responses API: #{caps[:responses_api]}"
      #   puts "Function calling: #{caps[:function_calling]}"
      #   puts "Handoffs: #{caps[:handoffs]}"
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

      private

      ##
      # Convert Responses API input items to messages
      #
      # This method converts Responses API input items back to the standard
      # message format that chat_completion expects. This enables seamless
      # conversation continuation across different API formats.
      #
      # @example Converting input items
      #   input = [
      #     { type: "message", role: "user", content: "Hello" },
      #     { type: "function_call_output", call_id: "call_123", output: "Success" }
      #   ]
      #   messages = convert_input_to_messages(input, base_messages)
      #   # Returns: [...base_messages, { role: "user", content: "Hello" }, 
      #   #           { role: "tool", tool_call_id: "call_123", content: "Success" }]
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
      # This method converts a Chat Completions API response to the Responses API
      # format, enabling universal handoff support across different provider types.
      #
      # @example Converting a chat completion response
      #   chat_response = {
      #     "choices" => [{
      #       "message" => {
      #         "role" => "assistant",
      #         "content" => "I'll help you",
      #         "tool_calls" => [{
      #           "id" => "call_123",
      #           "type" => "function",
      #           "function" => { "name" => "transfer_to_billing", "arguments" => "{}" }
      #         }]
      #       }
      #     }],
      #     "usage" => { "total_tokens" => 25 },
      #     "model" => "gpt-4"
      #   }
      #   
      #   responses_format = convert_chat_to_responses_format(chat_response)
      #   # Returns: {
      #   #   output: [
      #   #     { type: "message", role: "assistant", content: "I'll help you" },
      #   #     { type: "function_call", id: "call_123", name: "transfer_to_billing", arguments: "{}" }
      #   #   ],
      #   #   usage: { "total_tokens" => 25 },
      #   #   model: "gpt-4",
      #   #   id: "generated-uuid"
      #   # }
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
        {
          output: output,
          usage: response["usage"] || response[:usage],
          model: response["model"] || response[:model],
          id: response["id"] || response[:id] || SecureRandom.uuid
        }
      end
    end
  end
end