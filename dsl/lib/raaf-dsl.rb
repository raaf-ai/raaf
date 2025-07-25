# frozen_string_literal: true

require_relative "../../core/lib/raaf-core"
require_relative "raaf/dsl/core/version"
require "active_support/all"

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
#   class MyAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::Agents::AgentDsl
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
#   class ResearchAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::Agents::AgentDsl
#
#     agent_name "ResearchAgent"
#     uses_tool :web_search
#     tool_choice "required"  # Must use a tool before responding
#   end
#
# @example Agent with specific tool enforcement
#   class WebSearchAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::Agents::AgentDsl
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
module RAAF
  module DSL
    # Base error class for all AI Agent DSL related errors
    #
    # This error class serves as the parent for all custom exceptions raised
    # by the AI Agent DSL framework. It provides a consistent error hierarchy
    # and makes it easy to rescue from any framework-related errors.
    #
    # @example Rescuing from any framework error
    #   begin
    #     agent.run
    #   rescue RAAF::DSL::Error => e
    #     Rails.logger.error "AI Agent DSL error: #{e.message}"
    #   end
    #
    class Error < StandardError; end

    # Auto-require core components
    autoload :AgentBuilder, "raaf/dsl/builders/agent_builder"
    autoload :Config, "raaf/dsl/config/config"
    autoload :ConfigurationBuilder, "raaf/dsl/builders/configuration_builder"
    autoload :ContextVariables, "raaf/dsl/core/context_variables"
    autoload :Prompt, "raaf/dsl/prompts"
    autoload :PromptConfiguration, "raaf/dsl/config/prompt_configuration"
    autoload :PromptResolver, "raaf/dsl/prompts/prompt_resolver"
    autoload :PromptResolverRegistry, "raaf/dsl/prompts/prompt_resolver"
    autoload :Railtie, "raaf/dsl/railtie"
    autoload :SwarmDebugger, "raaf/dsl/debugging/swarm_debugger"
    autoload :ToolBuilder, "raaf/dsl/builders/tool_builder"
    autoload :ToolDsl, "raaf/dsl/tool_dsl"
    autoload :ToolRegistry, "raaf/dsl/core/tool_registry"
    autoload :WorkflowBuilder, "raaf/dsl/builders/workflow_builder"

    # AI Agent classes and base functionality
    #
    # This module contains all agent-related classes including the base agent
    # class and any specialized agent types. Agents are the core execution
    # units that orchestrate AI interactions, tool usage, and workflow management.
    #
    # @example Creating a custom agent
    #   class MyAgent < RAAF::DSL::Agents::Base
    #     include RAAF::DSL::Agents::AgentDsl
    #     agent_name "my_agent"
    #   end
    #
    module Agents
      autoload :Base, "raaf/dsl/agents/base"
      autoload :AgentDsl, "raaf/dsl/agents/agent_dsl"
    end

    # Force load of AgentDsl module for tests
    require_relative "raaf/dsl/agents/agent_dsl"

    # Prompt building and template system
    #
    # This module contains the prompt system classes that handle the generation
    # of system and user prompts with variable contracts, context mapping, and
    # validation. Prompts are Phlex-inspired templates that provide type-safe
    # prompt construction with clear variable requirements.
    #
    # @example Creating a custom prompt
    #   class MyPrompt < RAAF::DSL::Prompts::Base
    #     requires :company_name
    #     def system
    #       "You are analyzing #{company_name}"
    #     end
    #   end
    #
    module Prompts
      autoload :Base, "raaf/dsl/prompts/base"
    end

    # Prompt resolvers for different formats
    #
    # This module contains resolvers that handle different prompt formats
    # including Phlex-style classes, Markdown files, and ERB templates.
    #
    # @example Using prompt resolution
    #   prompt = RAAF::DSL::Prompt.resolve("customer_service.md")
    #   prompt = RAAF::DSL::Prompt.resolve(MyPromptClass)
    #   prompt = RAAF::DSL::Prompt.resolve("template.md.erb", name: "John")
    #
    module PromptResolvers
      autoload :PhlexResolver, "raaf/dsl/prompts/phlex_resolver"
      autoload :FileResolver, "raaf/dsl/prompts/file_resolver"
    end

    # Tool integration and execution framework
    #
    # This module contains all tool-related classes including the base tool
    # class and specific tool implementations. Tools provide external functionality
    # to agents such as web search, API calls, data processing, and other
    # computational tasks with parameter validation and error handling.
    #
    # @example Using tools in agents
    #   class MyAgent < RAAF::DSL::Agents::Base
    #     include RAAF::DSL::Agents::AgentDsl
    #     uses_tool :web_search
    #   end
    #
    module Tools
      autoload :Base, "raaf/dsl/tools/base"
      autoload :WebSearch, "raaf/dsl/tools/web_search"
      autoload :WebSearchPresets, "raaf/dsl/tools/web_search_presets"
      autoload :TavilySearch, "raaf/dsl/tools/tavily_search"
    end

    # Debugging and inspection capabilities
    #
    # This module contains debugging tools for AI agent development including
    # LLM request/response interception, prompt inspection, and context debugging.
    # These tools provide comprehensive visibility into agent execution for
    # troubleshooting and optimization.
    #
    # @example Using debugging tools
    #   interceptor = RAAF::DSL::Debugging::LLMInterceptor.new
    #   interceptor.intercept_openai_calls do
    #     agent.run
    #   end
    #
    module Debugging
      autoload :LLMInterceptor, "raaf/dsl/debugging/llm_interceptor"
      autoload :PromptInspector, "raaf/dsl/debugging/prompt_inspector"
      autoload :ContextInspector, "raaf/dsl/debugging/context_inspector"
    end

    # Callback system for agent lifecycle events
    #
    # This module provides both global and agent-specific callback systems
    # for handling events during agent execution. It supports multiple handlers
    # per event type, executed in registration order.
    #
    # @example Global callbacks
    #   RAAF::DSL::Hooks::RunHooks.on_agent_start do |agent|
    #     puts "Agent #{agent.name} is starting"
    #   end
    #
    # @example Agent-specific callbacks
    #   class MyAgent < RAAF::DSL::Agents::Base
    #     include RAAF::DSL::Hooks::AgentHooks
    #
    #     on_start :log_start
    #     on_end { |agent, result| handle_completion(result) }
    #   end
    #
    module Hooks
      autoload :RunHooks, "raaf/dsl/hooks/run_hooks"
      autoload :AgentHooks, "raaf/dsl/hooks/agent_hooks"
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
      autoload :AgentGenerator, "raaf/dsl/generators/agent_generator"
      autoload :ConfigGenerator, "raaf/dsl/generators/config_generator"
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
      autoload :PromptMatchers, "raaf/dsl/rspec/prompt_matchers"
    end

    # Configure the gem with a block
    #
    # @example
    #   RAAF::DSL.configure do |config|
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

    # Configure prompt resolution
    #
    # @example
    #   RAAF::DSL.configure_prompts do |config|
    #     config.add_path "app/prompts"
    #     config.enable_resolver :erb, priority: 100
    #     config.disable_resolver :phlex
    #   end
    #
    def self.configure_prompts(&block)
      PromptConfiguration.configure(&block)
    end

    # Get the prompt configuration
    #
    # @return [PromptConfiguration] The current prompt configuration
    def self.prompt_configuration
      @prompt_configuration ||= PromptConfiguration.new
    end

    # Get the prompt resolver registry
    #
    # @return [PromptResolverRegistry] The prompt resolver registry
    def self.prompt_resolvers
      @prompt_resolvers ||= PromptResolverRegistry.new
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
end

# Rails integration
require "raaf/dsl/railtie" if defined?(Rails)
