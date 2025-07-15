# frozen_string_literal: true

require_relative "raaf/version"
require_relative "raaf/hash_utils"
require_relative "raaf/logging"
require_relative "raaf/agent"
require_relative "raaf/runner"
require_relative "raaf/run_config"
require_relative "raaf/function_tool"
require_relative "raaf/lifecycle"
require_relative "raaf/tracing"
require_relative "raaf/streaming"
require_relative "raaf/batch_processor"
require_relative "raaf/http_client"
require_relative "raaf/errors"

# Advanced features
require_relative "raaf/models/interface"
require_relative "raaf/models/openai_provider"
require_relative "raaf/models/anthropic_provider"
require_relative "raaf/models/multi_provider"
require_relative "raaf/guardrails"
require_relative "raaf/structured_output"
require_relative "raaf/result"
require_relative "raaf/tracing/spans"
require_relative "raaf/tracing/trace_provider"
require_relative "raaf/tracing/batch_processor"
require_relative "raaf/tracing/openai_processor"
require_relative "raaf/tracing/otel_adapter"
require_relative "raaf/tracing/cost_manager"
require_relative "raaf/tracing/alert_engine"
require_relative "raaf/tracing/anomaly_detector"
require_relative "raaf/tracing/ai_analyzer"
require_relative "raaf/tracing/natural_language_query"
require_relative "raaf/visualization"
require_relative "raaf/debugging"
require_relative "raaf/repl"

# Advanced tools
require_relative "raaf/tools/file_search_tool"
require_relative "raaf/tools/web_search_tool"
require_relative "raaf/tools/computer_tool"
require_relative "raaf/tools/local_shell_tool"
require_relative "raaf/tools/mcp_tool"

# New advanced features
require_relative "raaf/run_result_streaming"
require_relative "raaf/streaming_events_semantic"
require_relative "raaf/tool_use_behavior"
require_relative "raaf/model_settings"
require_relative "raaf/parallel_guardrails"

# Additional advanced features
require_relative "raaf/voice/voice_workflow"
require_relative "raaf/configuration"
require_relative "raaf/extensions"
require_relative "raaf/handoffs/advanced_handoff"
require_relative "raaf/usage_tracking"

# Load ActiveRecord-dependent features only if ActiveRecord is available
if defined?(ActiveRecord)
  # Load Rails engine and ActiveRecord processor if Rails is available
  begin
    require "rails"
    require_relative "raaf/logging/rails_integration"
    require_relative "raaf/tracing/engine"
    require_relative "raaf/tracing/rails_integrations"
    require_relative "raaf/tracing/distributed_tracer"
  rescue LoadError
    # Rails not available, skip Rails-specific components
  end
end

# Memory and Vector functionality
require_relative "raaf/memory"
begin
  require_relative "raaf/vector_store"
  require_relative "raaf/semantic_search"
rescue LoadError
  # Matrix gem not available, skip vector functionality
end

# Document processing
require_relative "raaf/multi_modal"
require_relative "raaf/data_pipeline"
require_relative "raaf/tools/document_tool"
require_relative "raaf/tools/vector_search_tool"
require_relative "raaf/tools/confluence_tool"

# Compliance and Security
require_relative "raaf/compliance"

##
# Ruby AI Agents Factory (RAAF) - A comprehensive framework for building multi-agent AI workflows
#
# This gem provides a Ruby implementation of AI Agents, offering a lightweight yet powerful
# framework for creating and managing AI agents with tool integration, handoffs, and tracing
# capabilities.
#
# == Features
#
# * Multi-agent workflows with specialized roles
# * Tool integration for custom functions
# * Agent handoffs for complex workflows
# * Streaming support for real-time responses
# * Comprehensive tracing and debugging
# * Provider-agnostic design (OpenAI, Anthropic, Gemini, etc.)
# * Guardrails for safety and validation
# * Structured outputs with schema validation
# * Interactive REPL for development
# * Visualization tools for workflow analysis
# * Computer automation capabilities
#
# == Quick Start
#
#   require 'ruby_ai_agents_factory'
#
#   # Create an agent
#   agent = RubyAIAgentsFactory::Agent.new(
#     name: "Assistant",
#     instructions: "You are a helpful assistant",
#     model: "gpt-4"
#   )
#
#   # Add a tool
#   def get_weather(city)
#     "The weather in #{city} is sunny"
#   end
#   agent.add_tool(method(:get_weather))
#
#   # Run the agent
#   runner = RubyAIAgentsFactory::Runner.new(agent: agent)
#   messages = [{ role: "user", content: "What's the weather in Paris?" }]
#   result = runner.run(messages)
#
# == Multi-Provider Support
#
#   # Use different providers
#   openai_agent = RubyAIAgentsFactory::Agent.new(
#     name: "OpenAI_Assistant",
#     model: "gpt-4"
#   )
#
#   claude_agent = RubyAIAgentsFactory::Agent.new(
#     name: "Claude_Assistant",
#     model: "claude-3-sonnet-20240229"
#   )
#
# == Advanced Features
#
#   # Guardrails for safety
#   guardrails = RubyAIAgentsFactory::Guardrails::GuardrailManager.new
#   guardrails.add_guardrail(RubyAIAgentsFactory::Guardrails::ContentSafetyGuardrail.new)
#
#   # Enhanced tracing
#   tracer = RubyAIAgentsFactory::Tracing::SpanTracer.new
#   tracer.add_processor(RubyAIAgentsFactory::Tracing::ConsoleSpanProcessor.new)
#
#   # Interactive development
#   repl = RubyAIAgentsFactory::REPL.new(agent: agent)
#   repl.start
#
# == Configuration
#
# Set environment variables for API keys:
#
#   export OPENAI_API_KEY="your-openai-key"
#   export ANTHROPIC_API_KEY="your-anthropic-key"
#   export GEMINI_API_KEY="your-gemini-key"
#
# @author Ruby AI Agents Factory Team
# @version 0.1.0
# @since 0.1.0
module RubyAIAgentsFactory
  ##
  # Base error class for all Ruby AI Agents Factory exceptions
  #
  # All custom exceptions in the Ruby AI Agents Factory framework inherit from this class,
  # providing a consistent error hierarchy for exception handling.
  #
  # @example Catching all RAAF errors
  #   begin
  #     agent.run(messages)
  #   rescue RubyAIAgentsFactory::Error => e
  #     puts "Ruby AI Agents Factory error: #{e.message}"
  #   end
  class Error < StandardError; end

  ##
  # Global tracer access
  #
  # @return [RubyAIAgentsFactory::Tracing::SpanTracer] The global tracer instance
  def self.tracer(name = nil)
    Tracing::TraceProvider.tracer(name)
  end

  ##
  # Configure global tracing
  #
  # @yield [RubyAIAgentsFactory::Tracing::TraceProvider] The trace provider for configuration
  def self.configure_tracing(&)
    Tracing::TraceProvider.configure(&)
  end

  ##
  # Global logger access
  #
  # @return [RubyAIAgentsFactory::Logging] The unified logging system
  # @example
  #   RubyAIAgentsFactory.logger.info("Agent started", agent: "GPT-4")
  #   RubyAIAgentsFactory.logger.debug("Tool called", tool: "search")
  #   RubyAIAgentsFactory.logger.error("API failed", error: e.message)
  def self.logger
    @logger ||= Logging
  end
end