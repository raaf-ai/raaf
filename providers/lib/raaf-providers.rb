# frozen_string_literal: true

require "raaf-core"
require_relative "raaf/models/anthropic_provider"
require_relative "raaf/models/cohere_provider"
require_relative "raaf/models/groq_provider"
require_relative "raaf/models/ollama_provider"
require_relative "raaf/models/together_provider"
require_relative "raaf/models/multi_provider"
require_relative "raaf/models/retryable_provider"
require_relative "raaf/models/litellm_provider"

##
# RAAF Providers - Additional LLM provider integrations
#
# This gem extends RAAF Core with support for additional LLM providers
# beyond the default OpenAI providers. It includes integrations for
# Anthropic, Cohere, Groq, Ollama, Together, and more.
#
# == Supported Providers
#
# * Anthropic (Claude) - Advanced reasoning and safety
# * Cohere - Enterprise-focused language models
# * Groq - High-performance inference
# * Ollama - Local model hosting
# * Together - Open-source model hosting
# * LiteLLM - Universal LLM proxy
# * Multi-provider - Load balancing and failover
# * Retryable - Automatic retry logic
#
# == Usage
#
#   require 'raaf-providers'
#
#   # Use Anthropic's Claude
#   agent = RubyAIAgentsFactory::Agent.new(
#     name: "Claude Assistant",
#     instructions: "You are Claude, an AI assistant",
#     model: "claude-3-sonnet-20240229"
#   )
#
#   runner = RubyAIAgentsFactory::Runner.new(
#     agent: agent,
#     provider: RubyAIAgentsFactory::Models::AnthropicProvider.new
#   )
#
# == Multi-Provider Setup
#
#   # Load balancing across multiple providers
#   multi_provider = RubyAIAgentsFactory::Models::MultiProvider.new([
#     RubyAIAgentsFactory::Models::ResponsesProvider.new,
#     RubyAIAgentsFactory::Models::AnthropicProvider.new,
#     RubyAIAgentsFactory::Models::CohereProvider.new
#   ])
#
#   runner = RubyAIAgentsFactory::Runner.new(
#     agent: agent,
#     provider: multi_provider
#   )
#
# == Environment Variables
#
# Set API keys for the providers you want to use:
#
#   export ANTHROPIC_API_KEY="your-anthropic-key"
#   export COHERE_API_KEY="your-cohere-key"
#   export GROQ_API_KEY="your-groq-key"
#   export TOGETHER_API_KEY="your-together-key"
#
# @author Ruby AI Agents Factory Team
# @since 1.0.0
module RubyAIAgentsFactory
  module Providers
    # Providers gem version
    VERSION = "0.1.0"
  end
end
