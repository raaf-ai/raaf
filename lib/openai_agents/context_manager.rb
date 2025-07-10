# frozen_string_literal: true

require "tiktoken_ruby"

module OpenAIAgents
  # Manages conversation context size to stay within model token limits
  class ContextManager
    attr_reader :max_tokens, :preserve_system, :preserve_recent

    def initialize(model: "gpt-4o", max_tokens: nil, preserve_system: true, preserve_recent: 5)
      @model = model
      @max_tokens = max_tokens || default_max_tokens(model)
      @preserve_system = preserve_system
      @preserve_recent = preserve_recent
      @encoder = Tiktoken.encoding_for_model(model)
    rescue StandardError
      # Fallback to cl100k_base encoding if model not recognized
      @encoder = Tiktoken.get_encoding("cl100k_base")
    end

    # Main method to manage context size
    def manage_context(messages)
      return messages if messages.empty?

      # Quick check - if we're under limit, return as-is
      return messages if within_token_limit?(messages)

      # Apply token-based sliding window
      apply_token_sliding_window(messages)
    end

    # Count tokens for a single message
    def count_message_tokens(message)
      # Each message has overhead tokens for role and formatting
      tokens = 4 # Base overhead

      # Count role tokens
      tokens += @encoder.encode(message[:role] || "").length

      # Count content tokens
      tokens += @encoder.encode(message[:content]).length if message[:content]

      # Count tool calls if present
      tokens += estimate_tool_call_tokens(message[:tool_calls]) if message[:tool_calls]

      tokens
    end

    # Count total tokens for all messages
    def count_total_tokens(messages)
      # Base tokens for conversation structure
      total = 3

      messages.sum do |message|
        count_message_tokens(message)
      end + total
    end

    private

    def default_max_tokens(model)
      case model
      when /gpt-4o/, /gpt-4-turbo/
        120_000 # Leave some buffer from 128k limit
      when /gpt-4/
        7_500 # Leave buffer from 8k limit
      when /gpt-3.5-turbo-16k/
        15_000
      when /gpt-3.5/
        3_500
      else
        7_500 # Conservative default
      end
    end

    def within_token_limit?(messages)
      count_total_tokens(messages) <= @max_tokens
    end

    def apply_token_sliding_window(messages)
      # Separate system messages and regular messages
      system_messages = []
      regular_messages = []

      messages.each do |msg|
        if msg[:role] == "system" && @preserve_system
          system_messages << msg
        else
          regular_messages << msg
        end
      end

      # Always preserve recent messages
      recent_messages = regular_messages.last(@preserve_recent)
      older_messages = regular_messages[0...-@preserve_recent]

      # Start with system messages and recent messages
      result = system_messages + recent_messages
      current_tokens = count_total_tokens(result)

      # Add older messages from newest to oldest until we hit limit
      older_messages.reverse_each do |msg|
        msg_tokens = count_message_tokens(msg)

        break unless current_tokens + msg_tokens <= @max_tokens

        result.insert(system_messages.length, msg)
        current_tokens += msg_tokens

        # We've hit the limit
      end

      # Add truncation indicator if we dropped messages
      if result.length < messages.length
        truncation_msg = {
          role: "system",
          content: "[Note: #{messages.length - result.length} earlier messages were truncated to fit within token limits]"
        }
        result.insert(system_messages.length, truncation_msg)
      end

      result
    end

    def estimate_tool_call_tokens(tool_calls)
      # Rough estimate for tool calls
      tool_calls.sum do |tool_call|
        tokens = 10 # Base overhead

        if tool_call["function"]
          tokens += @encoder.encode(tool_call["function"]["name"] || "").length
          tokens += @encoder.encode(tool_call["function"]["arguments"] || "").length
        end

        tokens
      end
    end
  end
end
