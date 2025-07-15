# frozen_string_literal: true

require_relative "ai_agent_dsl/version"
require_relative "ai_agent_dsl/hash_utils"
require "active_support/all"
require "openai"

# AI Agent DSL - A Ruby framework for building intelligent AI agents
#
# This gem provides a declarative DSL for configuring AI agents with:
# - Environment-aware configuration management
# - Cost optimization features (model switching, max_turns control)
# - Phlex-like prompt system with variable contracts
# - Multi-agent workflow orchestration
# - Tool integration with parameter validation
# - YAML-based configuration with inheritance
#
# @example Basic agent definition
#   class MyAgent < AiAgentDsl::Agents::Base
#     include AiAgentDsl::AgentDsl
#
#     agent_name "MyAgent"
#     uses_tool :web_search
#     tool_choice "auto"  # Let AI decide when to use tools
#
#     schema do
#       field :results, type: :array, required: true
#     end
#   end
#
# @example Agent with required tool usage
#   class ResearchAgent < AiAgentDsl::Agents::Base
#     include AiAgentDsl::AgentDsl
#
#     agent_name "ResearchAgent"
#     uses_tool :web_search
#     tool_choice "required"  # Must use a tool before responding
#   end
#
# @example Agent with specific tool enforcement
#   class WebSearchAgent < AiAgentDsl::Agents::Base
#     include AiAgentDsl::AgentDsl
#
#     agent_name "WebSearchAgent"
#     uses_tool :web_search
#     uses_tool :calculator
#     tool_choice "web_search"  # Always use web_search tool
#   end
#
# @example Environment-specific configuration (config/ai_agents.yml)
#   development:
#     global:
#       model: "gpt-4o-mini"  # Use cheaper model in development
#       max_turns: 2
#       tool_choice: "auto"
#     agents:
#       my_agent:
#         max_turns: 1  # Even fewer turns for this specific agent
#       research_agent:
#         tool_choice: "required"  # Always require tool usage for research
#       analysis_agent:
#         tool_choice: { type: "function", function: { name: "web_search" } }
#
module AiAgentDsl
  # Base error class for all AI Agent DSL related errors
  #
  # This error class serves as the parent for all custom exceptions raised
  # by the AI Agent DSL framework. It provides a consistent error hierarchy
  # and makes it easy to rescue from any framework-related errors.
  #
  # @example Rescuing from any framework error
  #   begin
  #     agent.run
  #   rescue AiAgentDsl::Error => e
  #     Rails.logger.error "AI Agent DSL error: #{e.message}"
  #   end
  #
  class Error < StandardError; end

  # Auto-require core components
  autoload :AgentDsl, "ai_agent_dsl/agent_dsl"
  autoload :Config, "ai_agent_dsl/config"
  autoload :ToolDsl, "ai_agent_dsl/tool_dsl"
  autoload :ToolRegistry, "ai_agent_dsl/tool_registry"
  autoload :SchemaBuilder, "ai_agent_dsl/agent_dsl"
  autoload :ContextVariables, "ai_agent_dsl/context_variables"
  autoload :SwarmDebugger, "ai_agent_dsl/swarm_debugger"
  autoload :HashUtils, "ai_agent_dsl/hash_utils"
  autoload :Logging, "ai_agent_dsl/logging"
  autoload :Railtie, "ai_agent_dsl/railtie"

  # AI Agent classes and base functionality
  #
  # This module contains all agent-related classes including the base agent
  # class and any specialized agent types. Agents are the core execution
  # units that orchestrate AI interactions, tool usage, and workflow management.
  #
  # @example Creating a custom agent
  #   class MyAgent < AiAgentDsl::Agents::Base
  #     include AiAgentDsl::AgentDsl
  #     agent_name "my_agent"
  #   end
  #
  module Agents
    autoload :Base, "ai_agent_dsl/agents/base"
  end

  # Prompt building and template system
  #
  # This module contains the prompt system classes that handle the generation
  # of system and user prompts with variable contracts, context mapping, and
  # validation. Prompts are Phlex-inspired templates that provide type-safe
  # prompt construction with clear variable requirements.
  #
  # @example Creating a custom prompt
  #   class MyPrompt < AiAgentDsl::Prompts::Base
  #     requires :company_name
  #     def system
  #       "You are analyzing #{company_name}"
  #     end
  #   end
  #
  module Prompts
    autoload :Base, "ai_agent_dsl/prompts/base"
  end

  # Tool integration and execution framework
  #
  # This module contains all tool-related classes including the base tool
  # class and specific tool implementations. Tools provide external functionality
  # to agents such as web search, API calls, data processing, and other
  # computational tasks with parameter validation and error handling.
  #
  # @example Using tools in agents
  #   class MyAgent < AiAgentDsl::Agents::Base
  #     include AiAgentDsl::AgentDsl
  #     uses_tool :web_search
  #   end
  #
  module Tools
    autoload :Base, "ai_agent_dsl/tools/base"
    autoload :WebSearch, "ai_agent_dsl/tools/web_search"
    autoload :WebSearchPresets, "ai_agent_dsl/tools/web_search_presets"
    autoload :TavilySearch, "ai_agent_dsl/tools/tavily_search"
  end

  # Debugging and inspection capabilities
  #
  # This module contains debugging tools for AI agent development including
  # LLM request/response interception, prompt inspection, and context debugging.
  # These tools provide comprehensive visibility into agent execution for
  # troubleshooting and optimization.
  #
  # @example Using debugging tools
  #   interceptor = AiAgentDsl::Debugging::LLMInterceptor.new
  #   interceptor.intercept_openai_calls do
  #     agent.run
  #   end
  #
  module Debugging
    autoload :LLMInterceptor, "ai_agent_dsl/debugging/llm_interceptor"
    autoload :PromptInspector, "ai_agent_dsl/debugging/prompt_inspector"
    autoload :ContextInspector, "ai_agent_dsl/debugging/context_inspector"
  end

  # Callback system for agent lifecycle events
  #
  # This module provides both global and agent-specific callback systems
  # for handling events during agent execution. It supports multiple handlers
  # per event type, executed in registration order.
  #
  # @example Global callbacks
  #   AiAgentDsl::Hooks::RunHooks.on_agent_start do |agent|
  #     puts "Agent #{agent.name} is starting"
  #   end
  #
  # @example Agent-specific callbacks
  #   class MyAgent < AiAgentDsl::Agents::Base
  #     include AiAgentDsl::Hooks::AgentHooks
  #
  #     on_start :log_start
  #     on_end { |agent, result| handle_completion(result) }
  #   end
  #
  module Hooks
    autoload :RunHooks, "ai_agent_dsl/hooks/run_hooks"
    autoload :AgentHooks, "ai_agent_dsl/hooks/agent_hooks"
  end

  # Execution layer for agent runtime
  #
  # This module contains the minimal execution abstractions that the DSL
  # configures and delegates to. The DSL remains purely configurational
  # while these classes handle the actual execution details.
  #
  # @example DSL creates execution objects
  #   dsl_agent = MyAgent.new
  #   execution_agent = dsl_agent.create_agent  # Returns AiAgentDsl::Execution::Agent
  #   runner = AiAgentDsl::Execution::Runner.new(agent: execution_agent)
  #   result = runner.run(input)
  #
  module Execution
    autoload :Runner, "ai_agent_dsl/execution/runner"
  end

  # Rails generators for scaffolding AI agents and configuration
  #
  # This module contains Rails generators that help developers quickly create
  # agent classes, prompt classes, and configuration files following framework
  # conventions. The generators provide templates and ensure proper file
  # structure and naming conventions.
  #
  # @example Generating an agent
  #   rails generate ai_agent_dsl:agent MyAgent
  #   rails generate ai_agent_dsl:config
  #
  module Generators
    autoload :AgentGenerator, "ai_agent_dsl/generators/agent_generator"
    autoload :ConfigGenerator, "ai_agent_dsl/generators/config_generator"
  end

  # RSpec integration and custom matchers for testing
  #
  # This module provides custom RSpec matchers and helpers specifically designed
  # for testing AI Agent DSL components. It includes matchers for prompt testing,
  # validation, context handling, and content verification.
  #
  # @example Using RSpec matchers
  #   require 'ai_agent_dsl/rspec'
  #
  #   RSpec.describe MyPrompt do
  #     it "includes expected content" do
  #       expect(MyPrompt).to include_prompt_content("analysis")
  #         .with_context(document: "test.pdf")
  #     end
  #   end
  #
  module RSpec
    autoload :PromptMatchers, "ai_agent_dsl/rspec/prompt_matchers"
  end

  # Configure the gem with a block
  #
  # @example
  #   AiAgentDsl.configure do |config|
  #     config.config_file = "config/my_agents.yml"
  #     config.default_model = "gpt-4o-mini"
  #     config.default_tool_choice = "required"
  #   end
  #
  def self.configure
    yield(configuration)
  end

  # Get the current configuration
  #
  # @return [Configuration] The current configuration object
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Configuration object for the gem
  class Configuration
    attr_accessor :config_file, :default_model, :default_max_turns, :default_temperature, :default_tool_choice,
      :debug_enabled, :debug_level, :debug_output, :logging_level, :structured_logging, :enable_tracing

    def initialize
      @config_file = "config/ai_agents.yml"
      @default_model = "gpt-4o"
      @default_max_turns = 3
      @default_temperature = 0.7
      @default_tool_choice = "auto"
      @debug_enabled = false
      @debug_level = :standard  # :minimal, :standard, :verbose
      @debug_output = nil       # nil means use Rails.logger or STDOUT
      @logging_level = :info    # :debug, :info, :warn, :error, :fatal
      @structured_logging = true # Enable structured logging format
      @enable_tracing = nil # nil = auto-detect, true/false = force enable/disable
    end
  end
end

# Rails integration
require "ai_agent_dsl/railtie" if defined?(Rails)
