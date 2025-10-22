# frozen_string_literal: true

require "zeitwerk"
require "raaf-core"

# Set up Zeitwerk loader for RAAF providers
loader = Zeitwerk::Loader.for_gem
loader.tag = "raaf-providers"

# Configure inflections
loader.inflector.inflect(
  "litellm_provider" => "LiteLLMProvider"
)

# Setup the loader
loader.setup

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
# * Together - Open-source model hosting
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
#   export TOGETHER_API_KEY="your-together-key"
#
# @author Ruby AI Agents Factory Team
# @since 1.0.0
module RAAF
  module Providers
    # Load version from separate file to avoid duplication
  end
end

# Eager load if requested
loader.eager_load if ENV['RAAF_EAGER_LOAD'] == 'true'
