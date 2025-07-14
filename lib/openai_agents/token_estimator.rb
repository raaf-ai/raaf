# frozen_string_literal: true

# Try to load tiktoken for accurate token counting
begin
  require "tiktoken_ruby"
  USE_TIKTOKEN = true
rescue LoadError
  USE_TIKTOKEN = false
  warn "tiktoken_ruby not available. Using character-based token estimation. Run 'bundle install' to get accurate token counts." # rubocop:disable Layout/LineLength
end

module OpenAIAgents
  # Token estimation for OpenAI models when usage data is not provided
  # Uses tiktoken for accurate counting when available, falls back to character-based estimation
  class TokenEstimator
    # Token estimates per 1000 characters for different models
    # These are conservative estimates based on typical English text
    TOKEN_RATIOS = {
      # GPT-4 models use cl100k_base encoding
      "gpt-4" => 250, # ~4 chars per token
      "gpt-4-turbo" => 250,
      "gpt-4o" => 250,
      "gpt-4o-mini" => 250,

      # GPT-3.5 models use cl100k_base encoding
      "gpt-3.5-turbo" => 270, # ~3.7 chars per token

      # O1 models (reasoning models)
      "o1-preview" => 250,
      "o1-mini" => 250,

      # Default for unknown models
      "default" => 280 # Conservative estimate
    }.freeze

    # Additional tokens for message formatting overhead
    MESSAGE_OVERHEAD = 4 # tokens per message
    ROLE_TOKENS = 1 # tokens for role specification

    class << self
      # Estimates token usage for a chat completion request/response
      #
      # @param messages [Array<Hash>] Input messages
      # @param response_content [String, nil] Response content if available
      # @param model [String] Model name
      # @return [Hash] Estimated usage with input_tokens, output_tokens, total_tokens
      def estimate_usage(messages:, response_content: nil, model: "gpt-4")
        input_tokens = estimate_messages_tokens(messages, model)
        output_tokens = response_content ? estimate_text_tokens(response_content, model) : 0

        {
          "input_tokens" => input_tokens,
          "output_tokens" => output_tokens,
          "total_tokens" => input_tokens + output_tokens,
          "estimated" => true # Flag to indicate these are estimates
        }
      end

      # Estimates tokens for an array of messages
      #
      # @param messages [Array<Hash>] Messages array
      # @param model [String] Model name
      # @return [Integer] Estimated token count
      def estimate_messages_tokens(messages, model)
        return 0 unless messages.is_a?(Array)

        messages.sum do |message|
          estimate_message_tokens(message, model)
        end
      end

      # Estimates tokens for a single message
      #
      # @param message [Hash] Message hash with role and content
      # @param model [String] Model name
      # @return [Integer] Estimated token count
      def estimate_message_tokens(message, model)
        return 0 unless message.is_a?(Hash)

        if USE_TIKTOKEN
          # More accurate message token counting with tiktoken
          # Based on OpenAI's cookbook for counting tokens
          tokens_per_message = 3  # Every message follows <|im_start|>{role/name}\n{content}<|im_end|>\n
          tokens_per_name = 1     # If there's a name, the role is omitted

          tokens = tokens_per_message

          # Count role tokens
          role = message[:role] || message["role"] || ""
          tokens += estimate_text_tokens(role, model)

          # Count content tokens
          content = message[:content] || message["content"] || ""
          tokens += estimate_text_tokens(content, model)

          # Count name tokens if present
          if message[:name] || message["name"]
            name = message[:name] || message["name"]
            tokens += estimate_text_tokens(name, model) + tokens_per_name
          end
        else
          # Fallback to simple estimation
          tokens = MESSAGE_OVERHEAD + ROLE_TOKENS

          # Add content tokens
          content = message[:content] || message["content"] || ""
          tokens += estimate_text_tokens(content, model)
        end

        # Add tokens for tool calls if present
        if message[:tool_calls] || message["tool_calls"]
          tool_calls = message[:tool_calls] || message["tool_calls"]
          tokens += estimate_tool_calls_tokens(tool_calls, model)
        end

        tokens
      end

      # Estimates tokens for plain text
      #
      # @param text [String] Text to estimate
      # @param model [String] Model name
      # @return [Integer] Estimated token count
      def estimate_text_tokens(text, model)
        return 0 if text.nil? || text.empty?

        if USE_TIKTOKEN
          count_tokens_with_tiktoken(text, model)
        else
          # Fallback to character-based estimation
          char_count = text.length
          ratio = TOKEN_RATIOS[model] || TOKEN_RATIOS["default"]
          tokens = (char_count.to_f / 1000 * ratio).ceil
          [tokens, 1].max
        end
      end

      # Count tokens using tiktoken
      #
      # @param text [String] Text to count tokens for
      # @param model [String] Model name
      # @return [Integer] Exact token count
      def count_tokens_with_tiktoken(text, model)
        # Get the appropriate encoding for the model
        encoding = if model.start_with?("gpt-4")
                     Tiktoken.encoding_for_model("gpt-4")
                   elsif model.start_with?("gpt-3.5")
                     Tiktoken.encoding_for_model("gpt-3.5-turbo")
                   else
                     # Default to cl100k_base encoding for newer models
                     Tiktoken.get_encoding("cl100k_base")
                   end

        # Encode and count tokens
        tokens = encoding.encode(text)
        tokens.length
      rescue StandardError => e
        # If tiktoken fails, fall back to character estimation
        OpenAIAgents::Logging.warn("Tiktoken encoding failed, falling back to estimation", model: model, error: e.message, error_class: e.class.name)
        char_count = text.length
        ratio = TOKEN_RATIOS[model] || TOKEN_RATIOS["default"]
        tokens = (char_count.to_f / 1000 * ratio).ceil
        [tokens, 1].max
      end

      # Estimates tokens for tool calls
      #
      # @param tool_calls [Array] Tool calls array
      # @param model [String] Model name
      # @return [Integer] Estimated token count
      def estimate_tool_calls_tokens(tool_calls, model)
        return 0 unless tool_calls.is_a?(Array)

        tool_calls.sum do |tool_call|
          # Base overhead for tool call structure
          tokens = 10

          # Add tokens for function name
          if tool_call.is_a?(Hash)
            function = tool_call[:function] || tool_call["function"] || {}
            name = function[:name] || function["name"] || ""
            arguments = function[:arguments] || function["arguments"] || "{}"

            tokens += estimate_text_tokens(name, model)
            tokens += estimate_text_tokens(arguments.to_s, model)
          end

          tokens
        end
      end

      # Estimates tokens for a structured response format
      #
      # @param response_format [Hash] Response format specification
      # @param model [String] Model name
      # @return [Integer] Additional tokens for structured output
      def estimate_response_format_tokens(response_format, model)
        return 0 unless response_format.is_a?(Hash)

        # Structured outputs typically add overhead
        if response_format[:type] == "json_schema"
          # JSON schema adds significant overhead
          schema = response_format[:json_schema] || {}
          schema_text = schema.to_json
          estimate_text_tokens(schema_text, model) / 2 # Schema is referenced, not fully tokenized
        else
          5 # Basic format overhead
        end
      end

      # Get model base for token ratio selection
      #
      # @param model [String] Full model name
      # @return [String] Base model name for ratio lookup
      def model_base(model)
        return "default" unless model

        # Extract base model name
        base = model.split("-").first(2).join("-")
        TOKEN_RATIOS.key?(base) ? base : "default"
      end
    end
  end
end
