# frozen_string_literal: true

require "raaf-core"
require_relative "raaf/anthropic_provider"
require_relative "raaf/cohere_provider"
require_relative "raaf/groq_provider"
require_relative "raaf/perplexity_provider"
require_relative "raaf/gemini_provider"
require_relative "raaf/together_provider"
require_relative "raaf/moonshot_provider"
require_relative "raaf/multi_provider"
require_relative "raaf/litellm_provider"
require_relative "raaf/xai_provider"

##
# RAAF Providers - Additional LLM provider integrations
#
# This gem extends RAAF Core with support for additional LLM providers
# beyond the default OpenAI providers. It includes integrations for
# Anthropic, Cohere, Groq, Together, and more.
#
# == Supported Providers
#
# * Anthropic (Claude) - Advanced reasoning and safety
# * Cohere - Enterprise-focused language models
# * Groq - High-performance inference
# * Perplexity - Web-grounded AI search with citations
# * Gemini - Google's multimodal AI models
# * Together - Open-source model hosting
# * Moonshot (Kimi K2) - Agentic AI with strong tool-calling and long-context support
# * xAI (Grok) - Real-time knowledge and reasoning models
# * LiteLLM - Universal LLM proxy
# * Multi-provider - Load balancing and failover
#
# All providers include built-in retry logic with exponential backoff.
#
# == Usage
#
#   require 'raaf-providers'
#
#   # Use Anthropic's Claude
#   agent = RAAF::Agent.new(
#     name: "Claude Assistant",
#     instructions: "You are Claude, an AI assistant",
#     model: "claude-3-sonnet-20240229"
#   )
#
#   runner = RAAF::Runner.new(
#     agent: agent,
#     provider: RAAF::Models::AnthropicProvider.new
#   )
#
# == Multi-Provider Setup
#
#   # Load balancing across multiple providers
#   multi_provider = RAAF::Models::MultiProvider.new([
#     RAAF::Models::ResponsesProvider.new,
#     RAAF::Models::AnthropicProvider.new,
#     RAAF::Models::CohereProvider.new
#   ])
#
#   runner = RAAF::Runner.new(
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
#   export PERPLEXITY_API_KEY="your-perplexity-key"
#   export GEMINI_API_KEY="your-gemini-key"
#   export TOGETHER_API_KEY="your-together-key"
#   export MOONSHOT_API_KEY="your-moonshot-key"
#   export XAI_API_KEY="your-xai-key"
#
# @author Ruby AI Agents Factory Team
# @since 1.0.0
module RAAF
  module Providers
    # Load version from separate file to avoid duplication
  end
end
