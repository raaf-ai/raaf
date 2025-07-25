# frozen_string_literal: true

require "json"

module RAAF

  ##
  # Item types for agent run operations
  #
  # The Items module provides classes and utilities for handling various types
  # of items that flow through agent conversations. This matches the Python SDK's
  # item structure for compatibility across implementations.
  #
  # Items represent different components of an agent conversation:
  # - Messages from the LLM
  # - Tool calls and their outputs
  # - Handoffs between agents
  # - Reasoning steps
  #
  # @example Working with items
  #   # Create a message output item
  #   item = Items::MessageOutputItem.new(
  #     agent: agent,
  #     raw_item: { "role" => "assistant", "content" => "Hello!" }
  #   )
  #
  #   # Extract content from messages
  #   content = Items::ItemHelpers.extract_message_content(message)
  #
  module Items

    ##
    # Base class for all run items
    #
    # RunItemBase provides the common interface for all item types that
    # flow through agent conversations. Each item has an associated agent
    # and raw data from the API.
    #
    class RunItemBase

      # @!attribute [r] agent
      #   @return [Agent] The agent associated with this item
      # @!attribute [r] raw_item
      #   @return [Hash] The raw API data for this item
      attr_reader :agent, :raw_item

      ##
      # Initialize a new run item
      #
      # @param agent [Agent] The agent that created or processed this item
      # @param raw_item [Hash] The raw API response data
      #
      def initialize(agent:, raw_item:)
        @agent = agent
        @raw_item = raw_item
      end

      ##
      # Converts this item to an input item suitable for passing to the model
      #
      # @return [Hash] The item in API input format
      # @raise [ArgumentError] If raw_item is not a Hash
      #
      def to_input_item
        raise ArgumentError, "Unexpected raw item type: #{@raw_item.class}" unless @raw_item.is_a?(Hash)

        @raw_item
      end

    end

    ##
    # Represents a message from the LLM
    #
    # MessageOutputItem encapsulates assistant messages generated by the model,
    # including text responses and structured content.
    #
    class MessageOutputItem < RunItemBase

      ##
      # @return [String] The item type identifier
      def type
        "message_output_item"
      end

    end

    ##
    # Represents a tool call for handoff between agents
    #
    # HandoffCallItem represents a request to transfer control from one
    # agent to another during a conversation.
    #
    class HandoffCallItem < RunItemBase

      ##
      # @return [String] The item type identifier
      def type
        "handoff_call_item"
      end

    end

    ##
    # Represents the output of a handoff
    #
    # HandoffOutputItem captures the result of a handoff operation,
    # including information about the source and target agents.
    #
    class HandoffOutputItem < RunItemBase

      # @!attribute [r] source_agent
      #   @return [Agent] The agent handing off control
      # @!attribute [r] target_agent
      #   @return [Agent] The agent receiving control
      attr_reader :source_agent, :target_agent

      ##
      # Initialize a handoff output item
      #
      # @param agent [Agent] The agent processing this item
      # @param raw_item [Hash] The raw API data
      # @param source_agent [Agent] The agent initiating the handoff
      # @param target_agent [Agent] The agent receiving control
      #
      def initialize(agent:, raw_item:, source_agent:, target_agent:)
        super(agent: agent, raw_item: raw_item)
        @source_agent = source_agent
        @target_agent = target_agent
      end

      ##
      # @return [String] The item type identifier
      def type
        "handoff_output_item"
      end

    end

    ##
    # Represents a tool call
    #
    # ToolCallItem represents a request to execute a tool (function,
    # computer action, web search, etc.) during agent execution.
    #
    class ToolCallItem < RunItemBase

      ##
      # @return [String] The item type identifier
      def type
        "tool_call_item"
      end

      ##
      # Convert tool call item to input format
      #
      # For Responses API, tool calls should be converted to function_call format
      # instead of maintaining the internal tool_call format.
      #
      # @return [Hash] The item in API input format
      def to_input_item
        raise ArgumentError, "Unexpected raw item type: #{@raw_item.class}" unless @raw_item.is_a?(Hash)

        # Convert from internal tool_call format to Responses API function_call format
        {
          type: "function_call",
          name: @raw_item[:name] || @raw_item["name"],
          arguments: @raw_item[:arguments] || @raw_item["arguments"],
          call_id: @raw_item[:id] || @raw_item["id"]
        }
      end

    end

    ##
    # Represents the output of a tool call
    #
    # ToolCallOutputItem captures the result of executing a tool,
    # including any data or error information returned.
    #
    class ToolCallOutputItem < RunItemBase

      # @!attribute [r] output
      #   @return [Object] The tool execution output
      attr_reader :output

      ##
      # Initialize a tool call output item
      #
      # @param agent [Agent] The agent processing this item
      # @param raw_item [Hash] The raw API data
      # @param output [Object] The tool execution result
      #
      def initialize(agent:, raw_item:, output:)
        super(agent: agent, raw_item: raw_item)
        @output = output
      end

      ##
      # @return [String] The item type identifier
      def type
        "tool_call_output_item"
      end

    end

    ##
    # Represents the output of a function call (alias for ToolCallOutputItem)
    #
    # FunctionCallOutputItem is used specifically for function_call_output items
    # in the OpenAI Responses API, matching the Python SDK structure.
    #
    class FunctionCallOutputItem < RunItemBase

      # @!attribute [r] output
      #   @return [Object] The function call output
      attr_reader :output

      ##
      # Initialize a function call output item
      #
      # @param agent [Agent] The agent processing this item
      # @param raw_item [Hash] The raw API data
      # @param output [Object] The function call result (optional)
      #
      def initialize(agent:, raw_item:, output: nil)
        super(agent: agent, raw_item: raw_item)
        @output = output || raw_item[:output] || raw_item["output"]
      end

      ##
      # @return [String] The item type identifier
      def type
        "function_call_output_item"
      end

    end

    ##
    # Represents a reasoning item
    #
    # ReasoningItem captures the model's internal reasoning process,
    # typically used with models that support chain-of-thought reasoning.
    #
    class ReasoningItem < RunItemBase

      ##
      # @return [String] The item type identifier
      def type
        "reasoning_item"
      end

    end

    ##
    # Model response container
    #
    # ModelResponse encapsulates the complete response from the model,
    # including output items, token usage, and response metadata.
    # This matches the Python SDK structure for cross-language compatibility.
    #
    class ModelResponse

      # @!attribute [r] output
      #   @return [Array<RunItemBase>] The output items from the model
      # @!attribute [r] usage
      #   @return [Hash] Token usage information
      # @!attribute [r] response_id
      #   @return [String, nil] Unique response identifier
      attr_reader :output, :usage, :response_id

      ##
      # Initialize a model response
      #
      # @param output [Array<RunItemBase>] Output items from the model
      # @param usage [Hash] Token usage data (input_tokens, output_tokens, etc.)
      # @param response_id [String, nil] Optional response identifier
      #
      def initialize(output:, usage:, response_id: nil)
        @output = output
        @usage = usage
        @response_id = response_id
      end

      ##
      # Convert output to input items suitable for passing to the model
      #
      # @return [Array<Hash>] Array of items in API input format
      # @raise [ArgumentError] If an item cannot be converted
      #
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

    ##
    # Helper methods for working with items and messages
    #
    # ItemHelpers provides utility methods for extracting content from messages,
    # converting between different message formats, and creating standard message
    # structures. These helpers ensure consistent handling of the various message
    # formats used by different OpenAI APIs.
    #
    class ItemHelpers

      class << self

        ##
        # Extracts the last text content or refusal from a message
        #
        # @param message [Hash] Assistant message with content array
        # @return [String] The extracted text or empty string
        #
        # @example
        #   content = ItemHelpers.extract_last_content(message)
        #
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

        ##
        # Extracts the last text content from a message, ignoring refusals
        #
        # @param message [Hash] Assistant message with content array
        # @return [String, nil] The extracted text or nil if not found
        #
        def extract_last_text(message)
          return nil unless message.is_a?(Hash) && message["role"] == "assistant"

          content = message["content"]
          return nil unless content.is_a?(Array) && !content.empty?

          last_content = content.last
          return nil unless last_content["type"] == "output_text"

          last_content["text"]
        end

        ##
        # Converts a string or list of input items into a list of input items
        #
        # Handles conversion between different input formats to ensure compatibility
        # with the Responses API input item structure.
        #
        # @param input [String, Array] User input as string or array of items
        # @return [Array<Hash>] Array of input items in API format
        # @raise [ArgumentError] If input type is not supported
        #
        # @example Convert string input
        #   items = ItemHelpers.input_to_new_input_list("Hello")
        #   # => [{ "type" => "message", "role" => "user", "content" => [{ "type" => "text", "text" => "Hello" }] }]
        #
        def input_to_new_input_list(input)
          case input
          when String
            # For Responses API, use proper input item format
            [{
              "type" => "message",
              "role" => "user",
              "content" => [{ "type" => "text", "text" => input }]
            }]
          when Array
            # Check if it's already in input item format or needs conversion
            if input.first && input.first["role"] && !input.first["type"]
              # Convert from message format to input items (has role but no type)
              convert_messages_to_input_items(input)
            else
              # Already in input item format or empty array
              input.dup
            end
          else
            raise ArgumentError, "Input must be string or array, got #{input.class}"
          end
        end

        ##
        # Convert chat messages to Responses API input items
        #
        # Transforms Chat Completions API message format into Responses API
        # input item format for compatibility.
        #
        # @param messages [Array<Hash>] Array of chat messages
        # @return [Array<Hash>] Array of input items
        #
        def convert_messages_to_input_items(messages)
          input_items = []

          messages.each do |msg|
            role = msg["role"] || msg[:role]
            content = msg["content"] || msg[:content]

            case role
            when "user"
              input_items << { "type" => "message", "role" => "user", "content" => [{ "type" => "text", "text" => content }] }
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

        ##
        # Concatenates all text content from a list of message output items
        #
        # @param items [Array<MessageOutputItem>] Array of message output items
        # @return [String] Concatenated text content
        #
        def text_message_outputs(items)
          text = ""
          items.each do |item|
            text += text_message_output(item) if item.is_a?(MessageOutputItem)
          end
          text
        end

        ##
        # Extracts all text content from a single message output item
        #
        # @param message [MessageOutputItem] Message output item
        # @return [String] Extracted text content or empty string
        #
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

        ##
        # Creates a tool call output item from a tool call and its output
        #
        # @param tool_call [Hash] Tool call data with id/call_id
        # @param output [Object] Tool execution result
        # @return [Hash] Tool call output in API format
        #
        def tool_call_output_item(tool_call, output)
          {
            "call_id" => tool_call["call_id"] || tool_call["id"],
            "output" => output.is_a?(String) ? output : JSON.generate(output),
            "type" => "function_call_output"
          }
        end

        ##
        # Extract content from a standard message format
        #
        # Handles both string content and array-based content formats.
        #
        # @param message [Hash] Message with content field
        # @return [String] Extracted content or empty string
        #
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

        ##
        # Check if a message contains tool calls
        #
        # @param message [Hash] Message to check
        # @return [Boolean] True if message has tool calls
        #
        def tool_calls?(message)
          return false unless message.is_a?(Hash)

          tool_calls = message["tool_calls"] || message[:tool_calls]
          tool_calls.is_a?(Array) && !tool_calls.empty?
        end

        ##
        # Extract tool calls from a message
        #
        # @param message [Hash] Message potentially containing tool calls
        # @return [Array<Hash>] Array of tool call objects
        #
        def extract_tool_calls(message)
          return [] unless message.is_a?(Hash)

          tool_calls = message["tool_calls"] || message[:tool_calls]
          return [] unless tool_calls.is_a?(Array)

          tool_calls
        end

        ##
        # Create a user message
        #
        # @param content [String] Message content
        # @return [Hash] User message in standard format
        #
        def user_message(content)
          {
            "role" => "user",
            "content" => content
          }
        end

        ##
        # Create an assistant message
        #
        # @param content [String] Message content
        # @param tool_calls [Array<Hash>, nil] Optional tool calls
        # @return [Hash] Assistant message in standard format
        #
        def assistant_message(content, tool_calls: nil)
          message = {
            "role" => "assistant",
            "content" => content
          }
          message["tool_calls"] = tool_calls if tool_calls
          message
        end

        ##
        # Create a tool message
        #
        # @param tool_call_id [String] ID of the tool call this responds to
        # @param content [String] Tool execution result
        # @return [Hash] Tool message in standard format
        #
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
