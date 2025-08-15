# frozen_string_literal: true

require "tiktoken_ruby"

module RAAF

  ##
  # Token estimation for OpenAI models when usage data is not provided
  #
  # The TokenEstimator provides accurate token counting and estimation capabilities
  # for OpenAI models. It uses the tiktoken library for precise token counting.
  #
  # == Token Counting Methods
  #
  # * **Tiktoken Integration**: Precise token counting using OpenAI's tiktoken library
  # * **Message Format Aware**: Accounts for OpenAI's message formatting overhead
  # * **Tool Call Support**: Estimates tokens for function calls and arguments
  #
  # == Supported Models
  #
  # * **GPT-4 Family**: gpt-4, gpt-4-turbo, gpt-4o, gpt-4o-mini
  # * **GPT-3.5 Family**: gpt-3.5-turbo and variants
  # * **O1 Models**: o1-preview, o1-mini (reasoning models)
  # * **Generic Fallback**: Conservative estimates for unknown models
  #
  # == Usage Patterns
  #
  # The estimator is primarily used when actual usage data is not available
  # from the API response, providing cost estimation and quota management.
  #
  # @example Basic usage estimation
  #   messages = [
  #     { role: "user", content: "What's the weather like?" },
  #     { role: "assistant", content: "I'd be happy to help with weather information..." }
  #   ]
  #
  #   usage = TokenEstimator.estimate_usage(
  #     messages: messages,
  #     response_content: "The weather is sunny today.",
  #     model: "gpt-4o"
  #   )
  #   # => { "input_tokens" => 15, "output_tokens" => 8, "total_tokens" => 23, "estimated" => true }
  #
  # @example Text token estimation
  #   tokens = TokenEstimator.estimate_text_tokens("Hello, world!", "gpt-4")
  #   # => 3 (with tiktoken) or conservative estimate (without)
  #
  # @example Message array estimation
  #   conversation = [
  #     { role: "system", content: "You are a helpful assistant." },
  #     { role: "user", content: "Tell me about Ruby programming." }
  #   ]
  #   tokens = TokenEstimator.estimate_messages_tokens(conversation, "gpt-4o")
  #
  # @example Tool call estimation
  #   message_with_tools = {
  #     role: "assistant",
  #     content: "I'll search for that information.",
  #     tool_calls: [{
  #       function: { name: "search", arguments: '{"query": "Ruby gems"}' }
  #     }]
  #   }
  #   tokens = TokenEstimator.estimate_message_tokens(message_with_tools, "gpt-4")
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see https://github.com/openai/tiktoken For the tiktoken tokenization library
  class TokenEstimator

    ##
    # Token estimates per 1000 characters for different models
    #
    # These are conservative estimates based on typical English text patterns.
    # Used as fallback when tiktoken is not available for precise counting.
    # Values represent approximate tokens per 1000 characters.
    #
    # @example Using ratios for estimation
    #   text_length = 4000  # characters
    #   model = "gpt-4o"
    #   ratio = TOKEN_RATIOS[model] || TOKEN_RATIOS["default"]
    #   estimated_tokens = (text_length / 1000.0 * ratio).ceil
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

    ##
    # Additional tokens for message formatting overhead
    #
    # OpenAI's chat completion format adds overhead tokens for message structure,
    # role specification, and formatting markers.

    # Base tokens added per message for formatting
    MESSAGE_OVERHEAD = 4

    # Additional tokens for role specification (user, assistant, system)
    ROLE_TOKENS = 1

    class << self

      ##
      # Estimates token usage for a chat completion request/response
      #
      # Provides comprehensive token usage estimation including input messages,
      # response content, and total token count. Returns format compatible with
      # OpenAI API usage data.
      #
      # @param messages [Array<Hash>] Input messages for the completion
      # @param response_content [String, nil] Response content if available
      # @param model [String] Model name for accurate estimation
      # @return [Hash] Estimated usage with input_tokens, output_tokens, total_tokens
      #
      # @example Complete usage estimation
      #   usage = estimate_usage(
      #     messages: conversation_messages,
      #     response_content: "Here's my response...",
      #     model: "gpt-4o"
      #   )
      #   puts "Total cost estimate: #{usage['total_tokens']} tokens"
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

      ##
      # Estimates tokens for an array of messages
      #
      # Calculates total token count for a conversation array, including
      # all message content, roles, and formatting overhead.
      #
      # @param messages [Array<Hash>] Messages array with role and content
      # @param model [String] Model name for appropriate token ratios
      # @return [Integer] Total estimated token count for all messages
      #
      # @example Conversation token estimation
      #   messages = [
      #     { role: "system", content: "You are helpful." },
      #     { role: "user", content: "Hello!" },
      #     { role: "assistant", content: "Hi there!" }
      #   ]
      #   total_tokens = estimate_messages_tokens(messages, "gpt-4")
      def estimate_messages_tokens(messages, model)
        return 0 unless messages.is_a?(Array)

        messages.sum do |message|
          estimate_message_tokens(message, model)
        end
      end

      ##
      # Estimates tokens for a single message
      #
      # Calculates token count for an individual message including content,
      # role, name (if present), tool calls, and formatting overhead.
      #
      # @param message [Hash] Message hash with role and content
      # @param model [String] Model name for token calculation
      # @return [Integer] Estimated token count for the message
      #
      # @example Simple message
      #   message = { role: "user", content: "What's the capital of France?" }
      #   tokens = estimate_message_tokens(message, "gpt-4o")
      #
      # @example Message with tool calls
      #   message = {
      #     role: "assistant",
      #     content: "I'll search for that.",
      #     tool_calls: [{ function: { name: "search", arguments: "{}" } }]
      #   }
      #   tokens = estimate_message_tokens(message, "gpt-4")
      def estimate_message_tokens(message, model)
        return 0 unless message.is_a?(Hash)

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

        # Add tokens for tool calls if present
        if message[:tool_calls] || message["tool_calls"]
          tool_calls = message[:tool_calls] || message["tool_calls"]
          tokens += estimate_tool_calls_tokens(tool_calls, model)
        end

        tokens
      end

      ##
      # Estimates tokens for plain text content
      #
      # Provides accurate token counting for text strings using tiktoken when
      # available, or character-based estimation as fallback.
      #
      # @param text [String] Text content to analyze
      # @param model [String] Model name for appropriate tokenization
      # @return [Integer] Estimated or exact token count
      #
      # @example Text analysis
      #   text = "The quick brown fox jumps over the lazy dog."
      #   tokens = estimate_text_tokens(text, "gpt-4o")
      #   # Returns precise count with tiktoken or conservative estimate
      def estimate_text_tokens(text, model)
        return 0 if text.nil? || text.empty?

        count_tokens_with_tiktoken(text, model)
      end

      ##
      # Count tokens using tiktoken for precise tokenization
      #
      # Uses OpenAI's tiktoken library to provide exact token counts matching
      # the tokenization used by OpenAI's models. Falls back to estimation
      # if tiktoken encounters errors.
      #
      # @param text [String] Text to count tokens for
      # @param model [String] Model name to determine encoding
      # @return [Integer] Exact token count
      #
      # @example Precise token counting
      #   tokens = count_tokens_with_tiktoken("Hello, world!", "gpt-4")
      #   # Returns exact token count as used by OpenAI
      #
      # @api private
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
        RAAF.logger.warn("Tiktoken encoding failed, falling back to estimation", model: model,
                                                                                   error: e.message, error_class: e.class.name)
        char_count = text.length
        ratio = TOKEN_RATIOS[model] || TOKEN_RATIOS["default"]
        tokens = (char_count.to_f / 1000 * ratio).ceil
        [tokens, 1].max
      end

      ##
      # Estimates tokens for tool calls in messages
      #
      # Calculates token overhead for function calls including function names,
      # arguments, and the structured format required by OpenAI's function calling.
      #
      # @param tool_calls [Array<Hash>] Tool calls array from message
      # @param model [String] Model name for token calculation
      # @return [Integer] Estimated token count for all tool calls
      #
      # @example Tool call estimation
      #   tool_calls = [{
      #     function: {
      #       name: "get_weather",
      #       arguments: '{"location": "New York", "units": "celsius"}'
      #     }
      #   }]
      #   tokens = estimate_tool_calls_tokens(tool_calls, "gpt-4")
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

      ##
      # Estimates tokens for structured response format specifications
      #
      # Calculates additional token overhead when using structured outputs
      # like JSON schema, which add formatting constraints and schema references.
      #
      # @param response_format [Hash] Response format specification
      # @param model [String] Model name for token calculation
      # @return [Integer] Additional tokens required for structured output
      #
      # @example JSON schema overhead
      #   format_spec = {
      #     type: "json_schema",
      #     json_schema: {
      #       name: "user_info",
      #       schema: { type: "object", properties: {...} }
      #     }
      #   }
      #   overhead = estimate_response_format_tokens(format_spec, "gpt-4")
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

      ##
      # Get model base for token ratio selection
      #
      # Extracts the base model family from full model names to select
      # appropriate token ratios for estimation.
      #
      # @param model [String] Full model name (e.g., "gpt-4o-2024-08-06")
      # @return [String] Base model name for ratio lookup (e.g., "gpt-4o")
      #
      # @example Model base extraction
      #   base = model_base("gpt-4o-2024-08-06")  # => "gpt-4o"
      #   base = model_base("custom-model-v1")    # => "default"
      #
      # @api private
      def model_base(model)
        return "default" unless model

        # Extract base model name
        base = model.split("-").first(2).join("-")
        TOKEN_RATIOS.key?(base) ? base : "default"
      end

    end

  end

end
