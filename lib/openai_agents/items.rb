# frozen_string_literal: true

require "json"

module OpenAIAgents
  # Item types matching Python SDK
  module Items
    # Base class for all run items
    class RunItemBase
      attr_reader :agent, :raw_item

      def initialize(agent:, raw_item:)
        @agent = agent
        @raw_item = raw_item
      end

      # Converts this item to an input item suitable for passing to the model
      def to_input_item
        raise ArgumentError, "Unexpected raw item type: #{@raw_item.class}" unless @raw_item.is_a?(Hash)

        @raw_item
      end
    end

    # Represents a message from the LLM
    class MessageOutputItem < RunItemBase
      def type
        "message_output_item"
      end
    end

    # Represents a tool call for handoff between agents
    class HandoffCallItem < RunItemBase
      def type
        "handoff_call_item"
      end
    end

    # Represents the output of a handoff
    class HandoffOutputItem < RunItemBase
      attr_reader :source_agent, :target_agent

      def initialize(agent:, raw_item:, source_agent:, target_agent:)
        super(agent: agent, raw_item: raw_item)
        @source_agent = source_agent
        @target_agent = target_agent
      end

      def type
        "handoff_output_item"
      end
    end

    # Represents a tool call (function, computer action, etc.)
    class ToolCallItem < RunItemBase
      def type
        "tool_call_item"
      end
    end

    # Represents the output of a tool call
    class ToolCallOutputItem < RunItemBase
      attr_reader :output

      def initialize(agent:, raw_item:, output:)
        super(agent: agent, raw_item: raw_item)
        @output = output
      end

      def type
        "tool_call_output_item"
      end
    end

    # Represents a reasoning item
    class ReasoningItem < RunItemBase
      def type
        "reasoning_item"
      end
    end

    # Model response matching Python SDK
    class ModelResponse
      attr_reader :output, :usage, :response_id

      def initialize(output:, usage:, response_id: nil)
        @output = output
        @usage = usage
        @response_id = response_id
      end

      # Convert output to input items suitable for passing to the model
      def to_input_items
        @output.map do |item|
          if item.respond_to?(:to_h)
            item.to_h
          elsif item.is_a?(Hash)
            item
          else
            raise ArgumentError, "Cannot convert item to input: #{item.class}"
          end
        end
      end
    end

    # Helper methods for working with items
    class ItemHelpers
      class << self
        # Extracts the last text content or refusal from a message
        def extract_last_content(message)
          return "" unless message.is_a?(Hash) && message["role"] == "assistant"

          content = message["content"]
          return "" unless content.is_a?(Array) && !content.empty?

          last_content = content.last
          case last_content["type"]
          when "output_text"
            last_content["text"] || ""
          when "refusal"
            last_content["refusal"] || ""
          else
            ""
          end
        end

        # Extracts the last text content from a message, ignoring refusals
        def extract_last_text(message)
          return nil unless message.is_a?(Hash) && message["role"] == "assistant"

          content = message["content"]
          return nil unless content.is_a?(Array) && !content.empty?

          last_content = content.last
          return nil unless last_content["type"] == "output_text"

          last_content["text"]
        end

        # Converts a string or list of input items into a list of input items
        def input_to_new_input_list(input)
          case input
          when String
            # For Responses API, use proper input item format
            [{
              "type" => "user_text",
              "text" => input
            }]
          when Array
            # Check if it's already in input item format or needs conversion
            if input.first && input.first["type"]
              # Already in input item format
              input.dup
            elsif input.first && input.first["role"]
              # Convert from message format to input items
              convert_messages_to_input_items(input)
            else
              input.dup
            end
          else
            raise ArgumentError, "Input must be string or array, got #{input.class}"
          end
        end
        
        # Convert chat messages to Responses API input items
        def convert_messages_to_input_items(messages)
          input_items = []
          
          messages.each do |msg|
            role = msg["role"] || msg[:role]
            content = msg["content"] || msg[:content]
            
            case role
            when "user"
              input_items << { "type" => "user_text", "text" => content }
            when "assistant"
              if msg["tool_calls"] || msg[:tool_calls]
                # Convert tool calls
                (msg["tool_calls"] || msg[:tool_calls]).each do |tc|
                  input_items << {
                    "type" => "function_call",
                    "name" => tc.dig("function", "name") || tc.dig(:function, :name),
                    "arguments" => tc.dig("function", "arguments") || tc.dig(:function, :arguments),
                    "call_id" => tc["id"] || tc[:id]
                  }
                end
              elsif content
                input_items << { "type" => "text", "text" => content }
              end
            when "tool"
              input_items << {
                "type" => "function_call_output",
                "call_id" => msg["tool_call_id"] || msg[:tool_call_id],
                "output" => content
              }
            end
          end
          
          input_items
        end

        # Concatenates all text content from a list of message output items
        def text_message_outputs(items)
          text = ""
          items.each do |item|
            text += text_message_output(item) if item.is_a?(MessageOutputItem)
          end
          text
        end

        # Extracts all text content from a single message output item
        def text_message_output(message)
          return "" unless message.is_a?(MessageOutputItem)

          raw_item = message.raw_item
          return "" unless raw_item.is_a?(Hash) && raw_item["content"].is_a?(Array)

          text = ""
          raw_item["content"].each do |content_part|
            text += content_part["text"] if content_part["type"] == "output_text"
          end
          text
        end

        # Creates a tool call output item from a tool call and its output
        def tool_call_output_item(tool_call, output)
          {
            "call_id" => tool_call["call_id"] || tool_call["id"],
            "output" => output.to_s,
            "type" => "function_call_output"
          }
        end

        # Extract content from a standard message format
        def extract_message_content(message)
          return "" unless message.is_a?(Hash)

          # Handle simple string content
          content = message["content"] || message[:content]
          return content if content.is_a?(String)

          # Handle array content (Responses API format)
          if content.is_a?(Array)
            text_parts = content.select { |part| part["type"] == "text" || part[:type] == :text }
            return text_parts.map { |part| part["text"] || part[:text] }.join
          end

          ""
        end

        # Check if a message contains tool calls
        def has_tool_calls?(message)
          return false unless message.is_a?(Hash)

          tool_calls = message["tool_calls"] || message[:tool_calls]
          tool_calls.is_a?(Array) && !tool_calls.empty?
        end

        # Extract tool calls from a message
        def extract_tool_calls(message)
          return [] unless message.is_a?(Hash)

          tool_calls = message["tool_calls"] || message[:tool_calls]
          return [] unless tool_calls.is_a?(Array)

          tool_calls
        end

        # Create a user message
        def user_message(content)
          {
            "role" => "user",
            "content" => content
          }
        end

        # Create an assistant message
        def assistant_message(content, tool_calls: nil)
          message = {
            "role" => "assistant",
            "content" => content
          }
          message["tool_calls"] = tool_calls if tool_calls
          message
        end

        # Create a tool message
        def tool_message(tool_call_id, content)
          {
            "role" => "tool",
            "tool_call_id" => tool_call_id,
            "content" => content
          }
        end
      end
    end
  end
end
