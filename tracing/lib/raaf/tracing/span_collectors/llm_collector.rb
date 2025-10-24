# frozen_string_literal: true

require_relative "base_collector"

module RAAF
  module Tracing
    module SpanCollectors
      # Specialized collector for LLM completions that captures token usage, costs,
      # latency metrics, and model information. This collector provides detailed visibility
      # into LLM API calls and their financial impact.
      #
      # @example Basic usage
      #   completion = { usage: { input_tokens: 1250, output_tokens: 342 }, model: "gpt-4o" }
      #   collector = LLMCollector.new
      #   attributes = collector.collect_attributes(completion)
      #
      # @example Captured token information
      #   # Token usage
      #   attributes["llm.tokens.input"]              # => "1250"
      #   attributes["llm.tokens.output"]             # => "342"
      #   attributes["llm.tokens.cache_read"]         # => "500"
      #   attributes["llm.tokens.cache_creation"]     # => "100"
      #   attributes["llm.tokens.total"]              # => "2092"
      #
      # @example Captured cost information
      #   # Cost calculation (provider-specific pricing)
      #   attributes["llm.cost.input_cents"]          # => "1"
      #   attributes["llm.cost.output_cents"]         # => "1"
      #   attributes["llm.cost.cache_cents"]          # => "1"
      #   attributes["llm.cost.total_cents"]          # => "3"
      #
      # @example Captured latency information
      #   # Performance metrics
      #   attributes["llm.latency.total_ms"]          # => "2450"
      #   attributes["llm.model"]                     # => "gpt-4o"
      #
      # @note Token counts are converted to strings for JSONB storage
      # @note Costs are calculated in cents (multiply by 100) for precision
      # @note All metrics include fallback to "N/A" for missing values
      # @note Provider-specific pricing is used for cost calculations
      #
      # @see BaseCollector For DSL methods and common attribute handling
      # @see RAAF::Models::TokenCostCalculator For pricing calculations
      #
      # @since 1.0.0
      # @author RAAF Team
      class LLMCollector < BaseCollector
        # ============================================================================
        # TOKEN USAGE TRACKING
        # These attributes capture token counts from LLM API responses
        # ============================================================================

        # Input tokens (prompt tokens) sent to the LLM
        # Stored as: llm.tokens.input
        # @return [String] Number of input tokens or "N/A"
        span "tokens.input": ->(comp) do
          usage = extract_usage(comp)
          if usage
            (usage[:input_tokens] || usage["input_tokens"] || usage[:prompt_tokens] || usage["prompt_tokens"] || "N/A").to_s
          else
            "N/A"
          end
        end

        # Output tokens (completion tokens) returned by the LLM
        # Stored as: llm.tokens.output
        # @return [String] Number of output tokens or "N/A"
        span "tokens.output": ->(comp) do
          usage = extract_usage(comp)
          if usage
            (usage[:output_tokens] || usage["output_tokens"] || usage[:completion_tokens] || usage["completion_tokens"] || "N/A").to_s
          else
            "N/A"
          end
        end

        # Cache read tokens - input tokens served from cache (reduced cost)
        # Stored as: llm.tokens.cache_read
        # @return [String] Number of cached input tokens or "N/A"
        span "tokens.cache_read": ->(comp) do
          usage = extract_usage(comp)
          if usage
            cache_read = usage[:cache_read_input_tokens] || usage["cache_read_input_tokens"] || 0
            cache_read.zero? ? "N/A" : cache_read.to_s
          else
            "N/A"
          end
        end

        # Cache creation tokens - tokens cached for future use
        # Stored as: llm.tokens.cache_creation
        # @return [String] Number of tokens cached or "N/A"
        span "tokens.cache_creation": ->(comp) do
          usage = extract_usage(comp)
          if usage
            cache_creation = usage[:cache_creation_input_tokens] || usage["cache_creation_input_tokens"] || 0
            cache_creation.zero? ? "N/A" : cache_creation.to_s
          else
            "N/A"
          end
        end

        # Total tokens used (input + output)
        # Stored as: llm.tokens.total
        # @return [String] Total token count or "N/A"
        span "tokens.total": ->(comp) do
          usage = extract_usage(comp)
          if usage
            (usage[:total_tokens] || usage["total_tokens"] || "N/A").to_s
          else
            "N/A"
          end
        end

        # ============================================================================
        # COST TRACKING
        # These attributes calculate financial costs based on token usage and pricing
        # ============================================================================

        # Cost for input tokens (in cents: multiply by 100 for precision)
        # Calculated using provider-specific pricing
        # Stored as: llm.cost.input_cents
        # @return [String] Cost in cents or "N/A"
        span "cost.input_cents": ->(comp) do
          usage = extract_usage(comp)
          model = extract_model(comp)
          if usage && model
            input_tokens = usage[:input_tokens] || usage["input_tokens"] || 0
            cost_cents = calculate_input_cost_cents(model, input_tokens)
            cost_cents.round.to_s
          else
            "N/A"
          end
        end

        # Cost for output tokens (in cents)
        # Calculated using provider-specific pricing
        # Stored as: llm.cost.output_cents
        # @return [String] Cost in cents or "N/A"
        span "cost.output_cents": ->(comp) do
          usage = extract_usage(comp)
          model = extract_model(comp)
          if usage && model
            output_tokens = usage[:output_tokens] || usage["output_tokens"] || 0
            cost_cents = calculate_output_cost_cents(model, output_tokens)
            cost_cents.round.to_s
          else
            "N/A"
          end
        end

        # Cost savings from cached tokens (in cents)
        # Cached tokens are cheaper than fresh tokens
        # Stored as: llm.cost.cache_savings_cents
        # @return [String] Savings in cents or "N/A"
        span "cost.cache_savings_cents": ->(comp) do
          usage = extract_usage(comp)
          model = extract_model(comp)
          if usage && model
            cache_read = usage[:cache_read_input_tokens] || usage["cache_read_input_tokens"] || 0
            if cache_read > 0
              savings_cents = calculate_cache_savings_cents(model, cache_read)
              savings_cents.round.to_s
            else
              "N/A"
            end
          else
            "N/A"
          end
        end

        # Total cost (input + output - cache savings, in cents)
        # Stored as: llm.cost.total_cents
        # @return [String] Total cost in cents or "N/A"
        span "cost.total_cents": ->(comp) do
          usage = extract_usage(comp)
          model = extract_model(comp)
          if usage && model
            input_tokens = usage[:input_tokens] || usage["input_tokens"] || 0
            output_tokens = usage[:output_tokens] || usage["output_tokens"] || 0
            cache_read = usage[:cache_read_input_tokens] || usage["cache_read_input_tokens"] || 0

            input_cost = calculate_input_cost_cents(model, input_tokens)
            output_cost = calculate_output_cost_cents(model, output_tokens)
            savings_cost = calculate_cache_savings_cents(model, cache_read)

            total_cost = input_cost + output_cost - savings_cost
            total_cost.round.to_s
          else
            "N/A"
          end
        end

        # ============================================================================
        # LATENCY & PERFORMANCE METRICS
        # These attributes track timing information for the LLM call
        # ============================================================================

        # Total execution time for the LLM call (in milliseconds)
        # Stored as: llm.latency.total_ms
        # @return [String] Duration in milliseconds or "N/A"
        span "latency.total_ms": ->(comp) do
          if comp.respond_to?(:elapsed_time_ms) && comp.elapsed_time_ms
            comp.elapsed_time_ms.to_s
          else
            "N/A"
          end
        end

        # ============================================================================
        # MODEL & PROVIDER INFORMATION
        # These attributes track which model was used and provider details
        # ============================================================================

        # Model name used for this completion
        # @return [String] Model identifier (e.g., "gpt-4o")
        span model: ->(comp) do
          extract_model(comp) || "N/A"
        end

        # ============================================================================
        # PRIVATE HELPER METHODS
        # ============================================================================

        private

        # Extract usage hash from completion object
        # Handles both direct usage attribute and nested structures
        # @param comp [Object] Completion object from LLM provider
        # @return [Hash, nil] Usage data or nil if not found
        def self.extract_usage(comp)
          if comp.respond_to?(:usage)
            comp.usage
          else
            nil
          end
        end

        # Extract model name from completion object
        # @param comp [Object] Completion object from LLM provider
        # @return [String, nil] Model name or nil if not found
        def self.extract_model(comp)
          if comp.respond_to?(:model)
            comp.model
          else
            nil
          end
        end

        # Calculate input token cost based on model pricing
        # @param model [String] Model identifier
        # @param token_count [Integer] Number of input tokens
        # @return [Float] Cost in cents
        def self.calculate_input_cost_cents(model, token_count)
          pricing = TOKEN_PRICING[model] || TOKEN_PRICING["default"]
          (token_count / 1000.0) * pricing[:input_per_1k_cents]
        end

        # Calculate output token cost based on model pricing
        # @param model [String] Model identifier
        # @param token_count [Integer] Number of output tokens
        # @return [Float] Cost in cents
        def self.calculate_output_cost_cents(model, token_count)
          pricing = TOKEN_PRICING[model] || TOKEN_PRICING["default"]
          (token_count / 1000.0) * pricing[:output_per_1k_cents]
        end

        # Calculate savings from cached tokens
        # Cached tokens cost 90% less than regular tokens
        # @param model [String] Model identifier
        # @param token_count [Integer] Number of cached tokens
        # @return [Float] Savings in cents
        def self.calculate_cache_savings_cents(model, token_count)
          pricing = TOKEN_PRICING[model] || TOKEN_PRICING["default"]
          regular_cost = (token_count / 1000.0) * pricing[:input_per_1k_cents]
          cached_cost = (token_count / 1000.0) * pricing[:cached_input_per_1k_cents]
          regular_cost - cached_cost
        end

        # OpenAI pricing as of October 2024 (in cents per 1K tokens)
        TOKEN_PRICING = {
          "gpt-4o" => {
            input_per_1k_cents: 0.5,        # $0.005
            output_per_1k_cents: 1.5,       # $0.015
            cached_input_per_1k_cents: 0.05  # $0.0005 (90% cheaper)
          },
          "gpt-4o-mini" => {
            input_per_1k_cents: 0.075,       # $0.00075
            output_per_1k_cents: 0.3,        # $0.003
            cached_input_per_1k_cents: 0.0075 # 90% cheaper
          },
          "gpt-4-turbo" => {
            input_per_1k_cents: 1.0,         # $0.01
            output_per_1k_cents: 3.0,        # $0.03
            cached_input_per_1k_cents: 0.1   # 90% cheaper
          },
          "gpt-4" => {
            input_per_1k_cents: 3.0,         # $0.03
            output_per_1k_cents: 6.0,        # $0.06
            cached_input_per_1k_cents: 0.3   # 90% cheaper
          },
          "gpt-3.5-turbo" => {
            input_per_1k_cents: 0.05,        # $0.0005
            output_per_1k_cents: 0.15,       # $0.0015
            cached_input_per_1k_cents: 0.005 # 90% cheaper
          },
          "default" => {
            input_per_1k_cents: 0.5,         # Default to gpt-4o pricing
            output_per_1k_cents: 1.5,
            cached_input_per_1k_cents: 0.05
          }
        }.freeze
      end
    end
  end
end
