# frozen_string_literal: true

module RAAF
  # Usage tracking and cost calculation for LLM operations
  #
  # Provides normalization of token usage across different providers
  # and cost calculation based on current pricing.
  module Usage
    autoload :Normalizer, 'raaf/usage/normalizer'
    autoload :CostCalculator, 'raaf/usage/cost_calculator'
  end
end
