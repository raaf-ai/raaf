# frozen_string_literal: true

module RAAF
  module Usage
    # Normalizes token usage data from different providers into a canonical format
    #
    # All providers return different usage field names:
    # - OpenAI: prompt_tokens, completion_tokens, total_tokens
    # - Anthropic: input_tokens, output_tokens
    # - Gemini: promptTokenCount, candidatesTokenCount, totalTokenCount
    #
    # This normalizer converts all formats to the canonical format:
    #   {
    #     input_tokens: Integer,
    #     output_tokens: Integer,
    #     total_tokens: Integer,
    #     output_tokens_details: { reasoning_tokens: Integer },
    #     provider_metadata: { provider_name, model, raw_usage }
    #   }
    class Normalizer
      # Normalize provider usage data to canonical format
      #
      # @param response [Hash] Provider response containing usage data
      # @param provider_name [String] Name of the provider (e.g., "gemini", "anthropic")
      # @param model [String] Model identifier
      # @return [Hash, nil] Normalized usage hash or nil if no usage data
      def self.normalize(response, provider_name:, model:)
        usage = extract_usage_from_response(response)
        return nil unless usage && !usage.empty?

        {
          input_tokens: extract_input_tokens(usage),
          output_tokens: extract_output_tokens(usage),
          total_tokens: extract_total_tokens(usage),
          output_tokens_details: extract_output_details(usage),
          input_tokens_details: extract_input_details(usage),
          provider_metadata: {
            provider_name: provider_name,
            model: model,
            raw_usage: usage.dup
          }
        }.compact
      end

      private

      # Extract usage from response (handles both symbol and string keys)
      def self.extract_usage_from_response(response)
        response[:usage] || response["usage"]
      end

      # Extract input tokens (handles multiple naming conventions)
      # Tries: input_tokens -> prompt_tokens -> 0
      def self.extract_input_tokens(usage)
        usage[:input_tokens] || usage["input_tokens"] ||
        usage[:prompt_tokens] || usage["prompt_tokens"] || 0
      end

      # Extract output tokens (handles multiple naming conventions)
      # Tries: output_tokens -> completion_tokens -> 0
      def self.extract_output_tokens(usage)
        usage[:output_tokens] || usage["output_tokens"] ||
        usage[:completion_tokens] || usage["completion_tokens"] || 0
      end

      # Extract or calculate total tokens
      # Returns provided total or calculates from input + output
      def self.extract_total_tokens(usage)
        total = usage[:total_tokens] || usage["total_tokens"]
        return total if total && total > 0

        # Calculate if not provided
        extract_input_tokens(usage) + extract_output_tokens(usage)
      end

      # Extract output token details (reasoning tokens for o1 models)
      # Returns nil if no details present
      def self.extract_output_details(usage)
        details = {}

        # Reasoning tokens (o1, o3, reasoning models)
        reasoning = usage.dig(:output_tokens_details, :reasoning_tokens) ||
                   usage.dig("output_tokens_details", "reasoning_tokens")
        details[:reasoning_tokens] = reasoning if reasoning && reasoning > 0

        # Future: audio_tokens for multimodal

        details.empty? ? nil : details
      end

      # Extract input token details (cached tokens, etc.)
      # Returns nil if no details present
      def self.extract_input_details(usage)
        details = {}

        # Cached tokens (prompt caching - future)
        cached = usage.dig(:input_tokens_details, :cached_tokens) ||
                usage.dig("input_tokens_details", "cached_tokens")
        details[:cached_tokens] = cached if cached && cached > 0

        # Future: audio_tokens for multimodal

        details.empty? ? nil : details
      end
    end
  end
end
