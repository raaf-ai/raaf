# frozen_string_literal: true

require_relative "raaf/version"
require_relative "raaf/utils"
require_relative "raaf/logging"
require_relative "raaf/errors"
require_relative "raaf/guardrails"
require_relative "raaf/configuration"
require_relative "raaf/http_client"
require_relative "raaf/function_tool"
require_relative "raaf/models/interface"
require_relative "raaf/models/responses_provider"
require_relative "raaf/models/openai_provider"
require_relative "raaf/result"
require_relative "raaf/handoffs"
require_relative "raaf/context_manager"
require_relative "raaf/agent"

# Try to load retry provider functionality if available
begin
  require "raaf-providers"
rescue LoadError
  # raaf-providers gem not available - will use basic provider without retry
end

require_relative "raaf/runner"

##
# RAAF Core - Essential agent runtime with default OpenAI provider
#
# This is the core module of the Ruby AI Agents Factory (RAAF), providing
# the essential components needed to create and run AI agents. It includes
# the default OpenAI provider support and basic functionality.
#
# == Core Components
#
# * Agent - Main agent class for creating AI agents
# * Runner - Execution engine for agent conversations
# * FunctionTool - Tool integration framework
# * Result - Response handling and formatting
# * Default providers (OpenAI ResponsesProvider and OpenAIProvider)
#
# == Quick Start
#
#   require 'raaf-core'
#
#   # Create an agent with default OpenAI provider
#   agent = RAAF::Agent.new(
#     name: "Assistant",
#     instructions: "You are a helpful assistant",
#     model: "gpt-4o"
#   )
#
#   # Run the agent
#   runner = RAAF::Runner.new(agent: agent)
#   result = runner.run("Hello, how can you help me?")
#   puts result.messages.last[:content]
#
# == Adding Tools
#
#   # Define a simple tool
#   def get_weather(city)
#     "The weather in #{city} is sunny and 22°C"
#   end
#
#   # Add to agent
#   agent.add_tool(method(:get_weather))
#
# == Provider Support
#
# RAAF Core includes two OpenAI providers by default:
# * ResponsesProvider - Modern OpenAI Responses API (recommended)
# * OpenAIProvider - Legacy Chat Completions API (for compatibility)
#
# Additional providers are available in the raaf-providers gem.
#
# @author Ruby AI Agents Factory Team
# @since 1.0.0
module RAAF

  # Core gem version
  CORE_VERSION = "0.1.0"

end
