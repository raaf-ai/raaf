# frozen_string_literal: true

module RAAF
  module Continuation
    # Cost calculation for continuation operations
    #
    # Provides utilities to calculate API costs for continuation attempts
    # based on token usage and model pricing. Supports multiple pricing models
    # including standard OpenAI models and reasoning models.
    #
    # @example Calculate cost for a single request
    #   cost = CostCalculator.calculate("gpt-4o", 1000, 500)
    #   # => 0.0075
    #
    # @example Calculate cost for a continuation attempt
    #   total_cost = CostCalculator.calculate_total(
    #     model: "gpt-4o",
    #     attempts: [
    #       { input_tokens: 1000, output_tokens: 500 },
    #       { input_tokens: 1500, output_tokens: 750 }
    #     ]
    #   )
    #   # => 0.01875
    class CostCalculator
      # OpenAI model pricing (per 1k tokens)
      # Updated to reflect current OpenAI pricing
      # https://openai.com/pricing
      PRICING = {
        # GPT-4o models
        "gpt-4o" => { input: 0.005, output: 0.015 },
        "gpt-4o-2024-11-20" => { input: 0.005, output: 0.015 },
        "gpt-4o-2024-08-06" => { input: 0.005, output: 0.015 },
        "gpt-4o-mini" => { input: 0.00015, output: 0.0006 },
        "gpt-4o-mini-2024-07-18" => { input: 0.00015, output: 0.0006 },

        # GPT-4 models
        "gpt-4-turbo" => { input: 0.01, output: 0.03 },
        "gpt-4-turbo-2024-04-09" => { input: 0.01, output: 0.03 },
        "gpt-4" => { input: 0.03, output: 0.06 },

        # GPT-3.5 models
        "gpt-3.5-turbo" => { input: 0.0005, output: 0.0015 },
        "gpt-3.5-turbo-16k" => { input: 0.003, output: 0.004 },

        # o1 reasoning models (higher token costs due to reasoning)
        "o1-preview" => { input: 0.015, output: 0.06 },
        "o1-mini" => { input: 0.003, output: 0.012 },

        # GPT-5 models (projected pricing)
        "gpt-5" => { input: 0.01, output: 0.04 },
        "gpt-5-mini" => { input: 0.002, output: 0.008 },

        # Default fallback (use gpt-4o pricing)
      }.freeze

      # Reasoning token multiplier (reasoning tokens cost ~4x more than regular tokens)
      REASONING_TOKEN_MULTIPLIER = 4.0

      # Calculate cost for a single API call
      #
      # @param model [String] The model name (e.g., "gpt-4o", "gpt-4o-mini")
      # @param input_tokens [Integer] Number of input tokens consumed
      # @param output_tokens [Integer] Number of output tokens generated
      # @param reasoning_tokens [Integer] Number of reasoning tokens (o1/o5 models)
      #
      # @return [Float] Estimated cost in USD
      #
      # @example Basic usage
      #   CostCalculator.calculate("gpt-4o", 1000, 500)
      #   # => 0.0075 (1000 * 0.005/1000 + 500 * 0.015/1000)
      #
      # @example With reasoning tokens
      #   CostCalculator.calculate("o1-preview", 1000, 500, reasoning_tokens: 2000)
      #   # => 0.065 (includes 4x cost for reasoning tokens)
      #
      def self.calculate(model, input_tokens, output_tokens, reasoning_tokens: 0)
        pricing = PRICING[model] || PRICING["gpt-4o"]

        # Calculate base cost
        input_cost = (input_tokens * pricing[:input]) / 1000.0
        output_cost = (output_tokens * pricing[:output]) / 1000.0

        # Calculate reasoning token cost (if present)
        reasoning_cost = 0
        if reasoning_tokens.positive?
          # Reasoning tokens are already more expensive in the pricing model,
          # but the multiplier applies to the base output token pricing
          reasoning_output_pricing = pricing[:output] * REASONING_TOKEN_MULTIPLIER
          reasoning_cost = (reasoning_tokens * reasoning_output_pricing) / 1000.0
        end

        input_cost + output_cost + reasoning_cost
      end

      # Calculate total cost for multiple API calls
      #
      # @param model [String] The model name
      # @param attempts [Array<Hash>] Array of attempt data
      #   Each hash should contain:
      #   - :input_tokens [Integer] Input tokens for this attempt
      #   - :output_tokens [Integer] Output tokens for this attempt
      #   - :reasoning_tokens [Integer] Reasoning tokens (optional)
      #
      # @return [Float] Total cost in USD
      #
      # @example Calculate cost for multiple attempts
      #   CostCalculator.calculate_total(
      #     model: "gpt-4o",
      #     attempts: [
      #       { input_tokens: 1000, output_tokens: 500 },
      #       { input_tokens: 1500, output_tokens: 750 },
      #       { input_tokens: 2000, output_tokens: 1000 }
      #     ]
      #   )
      #   # => 0.03375
      #
      def self.calculate_total(model:, attempts: [])
        attempts.sum do |attempt|
          calculate(
            model,
            attempt[:input_tokens] || 0,
            attempt[:output_tokens] || 0,
            reasoning_tokens: attempt[:reasoning_tokens] || 0
          )
        end
      end

      # Estimate cost for a continuation attempt
      #
      # Convenience method for calculating cost of continuation operations
      # which typically have multiple attempts with increasing token usage.
      #
      # @param model [String] The model name
      # @param continuation_data [Hash] Continuation attempt data
      #   - :attempts [Integer] Number of continuation attempts
      #   - :tokens_per_attempt [Integer] Average tokens per attempt
      #
      # @return [Float] Estimated total cost in USD
      #
      # @example Estimate cost for continuation
      #   CostCalculator.estimate_continuation_cost(
      #     model: "gpt-4o",
      #     attempts: 3,
      #     tokens_per_attempt: 2000
      #   )
      #
      def self.estimate_continuation_cost(model:, attempts:, tokens_per_attempt:)
        # Rough estimate: assume 50% input, 50% output tokens per attempt
        attempt_data = attempts.times.map do |i|
          # Token usage typically increases with each attempt
          total_tokens = tokens_per_attempt * (i + 1)
          {
            input_tokens: (total_tokens * 0.5).to_i,
            output_tokens: (total_tokens * 0.5).to_i
          }
        end

        calculate_total(model: model, attempts: attempt_data)
      end

      # Get pricing for a specific model
      #
      # @param model [String] The model name
      # @return [Hash] Hash with :input and :output prices per 1k tokens
      #
      # @example
      #   pricing = CostCalculator.get_pricing("gpt-4o")
      #   # => { input: 0.005, output: 0.015 }
      #
      def self.get_pricing(model)
        PRICING[model] || PRICING["gpt-4o"]
      end

      # List all supported models
      #
      # @return [Array<String>] Array of supported model names
      #
      # @example
      #   CostCalculator.supported_models
      #   # => ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", ...]
      #
      def self.supported_models
        PRICING.keys
      end

      # Check if a model is supported
      #
      # @param model [String] The model name to check
      # @return [Boolean] true if model is supported, false otherwise
      #
      # @example
      #   CostCalculator.supports_model?("gpt-4o")
      #   # => true
      #   CostCalculator.supports_model?("unknown-model")
      #   # => false (uses default pricing)
      #
      def self.supports_model?(model)
        PRICING.key?(model)
      end

      # Format cost as currency string
      #
      # @param cost [Float] Cost in USD
      # @return [String] Formatted currency string
      #
      # @example
      #   CostCalculator.format_cost(0.0075)
      #   # => "$0.0075"
      #
      def self.format_cost(cost)
        "$#{format('%.4f', cost)}"
      end

      # Calculate cost and format as currency
      #
      # @param model [String] The model name
      # @param input_tokens [Integer] Input tokens
      # @param output_tokens [Integer] Output tokens
      # @param reasoning_tokens [Integer] Reasoning tokens (optional)
      #
      # @return [String] Formatted cost string
      #
      # @example
      #   CostCalculator.calculate_and_format("gpt-4o", 1000, 500)
      #   # => "$0.0075"
      #
      def self.calculate_and_format(model, input_tokens, output_tokens, reasoning_tokens: 0)
        cost = calculate(model, input_tokens, output_tokens, reasoning_tokens: reasoning_tokens)
        format_cost(cost)
      end
    end
  end
end
