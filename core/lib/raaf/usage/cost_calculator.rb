# frozen_string_literal: true

require_relative "pricing_data_manager"

module RAAF
  module Usage
    # Calculates costs for LLM usage across different providers and models
    #
    # Pricing is per 1M tokens and updated as of January 2025.
    # Pass normalized usage hash with model identifier to calculate costs.
    class CostCalculator
      # Pricing per 1M tokens (USD) - Updated January 2025
      PRICING = {
        # OpenAI
        "gpt-4o" => { input: 2.50, output: 10.00 },
        "gpt-4o-2024-11-20" => { input: 2.50, output: 10.00 },
        "gpt-4o-2024-08-06" => { input: 2.50, output: 10.00 },
        "gpt-4o-mini" => { input: 0.15, output: 0.60 },
        "gpt-4o-mini-2024-07-18" => { input: 0.15, output: 0.60 },
        "o1-preview" => { input: 15.00, output: 60.00 },
        "o1-preview-2024-09-12" => { input: 15.00, output: 60.00 },
        "o1-mini" => { input: 3.00, output: 12.00 },
        "o1-mini-2024-09-12" => { input: 3.00, output: 12.00 },
        "gpt-4-turbo" => { input: 10.00, output: 30.00 },
        "gpt-4-turbo-2024-04-09" => { input: 10.00, output: 30.00 },
        "gpt-4" => { input: 30.00, output: 60.00 },
        "gpt-3.5-turbo" => { input: 0.50, output: 1.50 },

        # Anthropic Claude
        "claude-3-5-sonnet-20241022" => { input: 3.00, output: 15.00 },
        "claude-3-5-sonnet-20240620" => { input: 3.00, output: 15.00 },
        "claude-3-5-haiku-20241022" => { input: 0.80, output: 4.00 },
        "claude-3-opus-20240229" => { input: 15.00, output: 75.00 },
        "claude-3-sonnet-20240229" => { input: 3.00, output: 15.00 },
        "claude-3-haiku-20240307" => { input: 0.25, output: 1.25 },

        # Google Gemini
        "gemini-2.5-flash" => { input: 0.15, output: 0.60 },
        "gemini-2.5-pro" => { input: 2.50, output: 10.00 },
        "gemini-2.0-flash-exp" => { input: 0.00, output: 0.00 }, # Free during preview
        "gemini-exp-1206" => { input: 0.00, output: 0.00 }, # Free during preview
        "gemini-1.5-pro" => { input: 1.25, output: 5.00 },
        "gemini-1.5-flash" => { input: 0.075, output: 0.30 },

        # Perplexity
        "perplexity" => { input: 0.20, output: 0.20 },
        "sonar" => { input: 0.20, output: 0.20 },
        "sonar-pro" => { input: 3.00, output: 15.00 },
        "sonar-reasoning" => { input: 5.00, output: 25.00 },

        # Groq
        "llama-3.3-70b-versatile" => { input: 0.59, output: 0.79 },
        "llama-3.1-70b-versatile" => { input: 0.59, output: 0.79 },
        "llama-3.1-8b-instant" => { input: 0.05, output: 0.08 },
        "mixtral-8x7b-32768" => { input: 0.24, output: 0.24 },
        "gemma-7b-it" => { input: 0.07, output: 0.07 },

        # Cohere
        "command-r-plus" => { input: 2.50, output: 10.00 },
        "command-r" => { input: 0.15, output: 0.60 },
        "command" => { input: 1.00, output: 2.00 },
        "command-light" => { input: 0.30, output: 0.60 },

        # xAI Grok
        "grok-beta" => { input: 5.00, output: 15.00 },

        # Moonshot
        "moonshot-v1-8k" => { input: 0.12, output: 0.12 },
        "moonshot-v1-32k" => { input: 0.24, output: 0.24 },
        "moonshot-v1-128k" => { input: 0.60, output: 0.60 }
      }.freeze

      # Calculate cost for a single usage record
      #
      # @param usage [Hash] Normalized usage hash with token counts
      # @param model [String] Model identifier for pricing lookup
      # @return [Hash, nil] Cost breakdown or nil if pricing unavailable
      #
      # @example
      #   usage = { input_tokens: 1000, output_tokens: 500 }
      #   CostCalculator.calculate_cost(usage, model: "gpt-4o")
      #   #=> {
      #     input_cost: 0.0025,
      #     output_cost: 0.005,
      #     total_cost: 0.0075,
      #     currency: "USD",
      #     pricing_date: "2025-01"
      #   }
      def self.calculate_cost(usage, model:)
        pricing = PRICING[model]
        return nil unless pricing

        input_tokens = usage[:input_tokens] || 0
        output_tokens = usage[:output_tokens] || 0

        # Calculate per 1M tokens
        input_cost = (input_tokens / 1_000_000.0) * pricing[:input]
        output_cost = (output_tokens / 1_000_000.0) * pricing[:output]

        {
          input_cost: input_cost.round(6),
          output_cost: output_cost.round(6),
          total_cost: (input_cost + output_cost).round(6),
          currency: "USD",
          pricing_date: "2025-01"
        }
      end

      # Calculate total cost across multiple usage records
      #
      # @param usages [Array<Hash>] Array of normalized usage hashes
      # @return [Hash] Aggregated cost breakdown
      #
      # @example
      #   usages = [
      #     { input_tokens: 1000, output_tokens: 500, provider_metadata: { model: "gpt-4o" } },
      #     { input_tokens: 2000, output_tokens: 1000, provider_metadata: { model: "gpt-4o-mini" } }
      #   ]
      #   CostCalculator.calculate_total_cost(usages)
      #   #=> { total_cost: 0.01, input_cost: 0.003, output_cost: 0.007, currency: "USD" }
      def self.calculate_total_cost(usages)
        total_input_cost = 0.0
        total_output_cost = 0.0

        usages.each do |usage|
          model = usage.dig(:provider_metadata, :model)
          next unless model

          cost = calculate_cost(usage, model: model)
          next unless cost

          total_input_cost += cost[:input_cost]
          total_output_cost += cost[:output_cost]
        end

        {
          input_cost: total_input_cost.round(6),
          output_cost: total_output_cost.round(6),
          total_cost: (total_input_cost + total_output_cost).round(6),
          currency: "USD"
        }
      end

      # Check if pricing is available for a model
      #
      # Checks both dynamic pricing data (from Helicone) and hardcoded PRICING constant.
      #
      # @param model [String] Model identifier
      # @return [Boolean] true if pricing is available
      def self.pricing_available?(model)
        # Try dynamic pricing first, then fall back to hardcoded
        pricing_manager = PricingDataManager.instance
        dynamic_pricing = pricing_manager.get_pricing(model)
        !dynamic_pricing.nil? || PRICING.key?(model)
      end

      # Get pricing information for a model
      #
      # Attempts to retrieve pricing from dynamic source (Helicone API via PricingDataManager)
      # first, then falls back to hardcoded PRICING constant if unavailable.
      #
      # @param model [String] Model identifier
      # @return [Hash, nil] Pricing hash or nil if unavailable
      #
      # @example Dynamic pricing (from Helicone)
      #   get_pricing("gpt-4o")
      #   # => { input: 2.50, output: 10.00, domain: "openai.com" }
      #
      # @example Fallback to hardcoded pricing
      #   get_pricing("gpt-4o") # If Helicone data is stale/unavailable
      #   # => { input: 2.50, output: 10.00 }
      def self.get_pricing(model)
        # Try dynamic pricing from PricingDataManager first
        pricing_manager = PricingDataManager.instance
        dynamic_pricing = pricing_manager.get_pricing(model)

        if dynamic_pricing
          RAAF.logger.debug "Using dynamic pricing for #{model} from Helicone"
          return dynamic_pricing
        end

        # Fall back to hardcoded PRICING constant
        if PRICING.key?(model)
          RAAF.logger.debug "Using hardcoded pricing for #{model} (Helicone data unavailable)"
          return PRICING[model]
        end

        # Model not found in either source
        RAAF.logger.warn "No pricing available for model: #{model}"
        nil
      end
    end
  end
end
