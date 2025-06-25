# frozen_string_literal: true

require_relative "openai_agents/version"
require_relative "openai_agents/agent"
require_relative "openai_agents/runner"
require_relative "openai_agents/run_config"
require_relative "openai_agents/function_tool"
require_relative "openai_agents/tracing"
require_relative "openai_agents/streaming"
require_relative "openai_agents/batch_processor"
require_relative "openai_agents/http_client"
require_relative "openai_agents/errors"

# Advanced features
require_relative "openai_agents/models/interface"
require_relative "openai_agents/models/openai_provider"
require_relative "openai_agents/models/anthropic_provider"
require_relative "openai_agents/models/multi_provider"
require_relative "openai_agents/guardrails"
require_relative "openai_agents/structured_output"
require_relative "openai_agents/result"
require_relative "openai_agents/tracing/spans"
require_relative "openai_agents/tracing/trace_provider"
require_relative "openai_agents/tracing/batch_processor"
require_relative "openai_agents/tracing/openai_processor"
require_relative "openai_agents/tracing/otel_adapter"
require_relative "openai_agents/visualization"
require_relative "openai_agents/debugging"
require_relative "openai_agents/repl"

# Advanced tools
require_relative "openai_agents/tools/file_search_tool"
require_relative "openai_agents/tools/web_search_tool"
require_relative "openai_agents/tools/computer_tool"
require_relative "openai_agents/tools/local_shell_tool"
require_relative "openai_agents/tools/mcp_tool"

# New advanced features
require_relative "openai_agents/run_result_streaming"
require_relative "openai_agents/streaming_events_semantic"
require_relative "openai_agents/tool_use_behavior"
require_relative "openai_agents/model_settings"
require_relative "openai_agents/parallel_guardrails"

# Additional advanced features
require_relative "openai_agents/voice/voice_workflow"
require_relative "openai_agents/configuration"
require_relative "openai_agents/extensions"
require_relative "openai_agents/handoffs/advanced_handoff"
require_relative "openai_agents/usage_tracking"

##
# OpenAI Agents Ruby - A comprehensive framework for building multi-agent AI workflows
#
# This gem provides a Ruby implementation of OpenAI Agents, offering a lightweight yet powerful
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
#   require 'openai_agents'
#
#   # Create an agent
#   agent = OpenAIAgents::Agent.new(
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
#   runner = OpenAIAgents::Runner.new(agent: agent)
#   messages = [{ role: "user", content: "What's the weather in Paris?" }]
#   result = runner.run(messages)
#
# == Multi-Provider Support
#
#   # Use different providers
#   openai_agent = OpenAIAgents::Agent.new(
#     name: "OpenAI_Assistant",
#     model: "gpt-4"
#   )
#
#   claude_agent = OpenAIAgents::Agent.new(
#     name: "Claude_Assistant",
#     model: "claude-3-sonnet-20240229"
#   )
#
# == Advanced Features
#
#   # Guardrails for safety
#   guardrails = OpenAIAgents::Guardrails::GuardrailManager.new
#   guardrails.add_guardrail(OpenAIAgents::Guardrails::ContentSafetyGuardrail.new)
#
#   # Enhanced tracing
#   tracer = OpenAIAgents::Tracing::SpanTracer.new
#   tracer.add_processor(OpenAIAgents::Tracing::ConsoleSpanProcessor.new)
#
#   # Interactive development
#   repl = OpenAIAgents::REPL.new(agent: agent)
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
# @author OpenAI Agents Ruby Team
# @version 0.1.0
# @since 0.1.0
module OpenAIAgents
  ##
  # Base error class for all OpenAI Agents exceptions
  #
  # All custom exceptions in the OpenAI Agents framework inherit from this class,
  # providing a consistent error hierarchy for exception handling.
  #
  # @example Catching all OpenAI Agents errors
  #   begin
  #     agent.run(messages)
  #   rescue OpenAIAgents::Error => e
  #     puts "OpenAI Agents error: #{e.message}"
  #   end
  class Error < StandardError; end

  ##
  # Global tracer access
  #
  # @return [OpenAIAgents::Tracing::SpanTracer] The global tracer instance
  def self.tracer(name = nil)
    Tracing::TraceProvider.tracer(name)
  end

  ##
  # Configure global tracing
  #
  # @yield [OpenAIAgents::Tracing::TraceProvider] The trace provider for configuration
  def self.configure_tracing(&)
    Tracing::TraceProvider.configure(&)
  end
end
