# frozen_string_literal: true

require "raaf-core"
require_relative "raaf/dsl/core/version"
require "active_support/all"

# Load ToolRegistry - required by agent tool integration for tool discovery
# ToolRegistry is defined in raaf-core/lib/raaf/tool_registry.rb (canonical location in core gem)
# AgentToolIntegration uses it for:
# - Tool registration at class definition time
# - Tool resolution at agent instantiation time
# Note: This is loaded automatically by raaf-core but included here for explicitness
require "raaf/tool_registry"

# Load tracing functionality
begin
  require "raaf/tracing/traceable"
rescue LoadError
  # Tracing functionality is optional - gracefully handle missing tracing gem
end

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
#   class MyAgent < RAAF::DSL::Agent
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
#   class ResearchAgent < RAAF::DSL::Agent
#     agent_name "ResearchAgent"
#     uses_tool :web_search
#     tool_choice "required"  # Must use a tool before responding
#   end
#
# @example Agent with specific tool enforcement
#   class WebSearchAgent < RAAF::DSL::Agent
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
    #     RAAF.logger.error "AI Agent DSL error: #{e.message}"
    #   end
    #
    class Error < StandardError; end

    # Load error classes first since they're used by other components
    require_relative "raaf/dsl/errors"
    
    # Auto-require core components
    autoload :AgentBuilder, "raaf/dsl/builders/agent_builder"
    autoload :AgentToolIntegration, "raaf/dsl/agent_tool_integration"
    autoload :AutoMerge, "raaf/dsl/auto_merge"
    autoload :Config, "raaf/dsl/config/config"
    autoload :ConfigurationBuilder, "raaf/dsl/builders/configuration_builder"
    autoload :ContextVariables, "raaf/dsl/core/context_variables"
    autoload :EdgeCases, "raaf/dsl/edge_cases"
    autoload :IncrementalConfig, "raaf/dsl/incremental_config"
    autoload :IncrementalProcessing, "raaf/dsl/incremental_processing"
    autoload :IncrementalProcessor, "raaf/dsl/incremental_processor"
    autoload :MergeStrategy, "raaf/dsl/merge_strategy"
    autoload :Prompt, "raaf/dsl/prompts"
    autoload :PromptConfiguration, "raaf/dsl/config/prompt_configuration"
    autoload :PromptResolver, "raaf/dsl/prompts/prompt_resolver"
    autoload :PromptResolverRegistry, "raaf/dsl/prompts/prompt_resolver"
    autoload :Railtie, "raaf/dsl/railtie"
    autoload :Result, "raaf/dsl/result"
    autoload :SwarmDebugger, "raaf/dsl/debugging/swarm_debugger"
    autoload :WorkflowBuilder, "raaf/dsl/builders/workflow_builder"
    
    # Builder classes
    module Builders
      autoload :ResultBuilder, "raaf/dsl/builders/result_builder"
    end

    # AI Agent classes and base functionality
    #
    # This module contains all agent-related classes including the base agent
    # class and any specialized agent types. Agents are the core execution
    # units that orchestrate AI interactions, tool usage, and workflow management.
    #
    # @example Creating a custom agent
    #   class MyAgent < RAAF::DSL::Agent
    #     agent_name "my_agent"
    #   end
    #
    module Agents
      # AgentDsl functionality has been consolidated into the unified Agent class
      autoload :ContextValidation, "raaf/dsl/agents/context_validation"
    end

    # Main Agent class - the unified agent with all features
    autoload :Agent, "raaf/dsl/agent"
    
    # Service base class for non-LLM operations
    autoload :Service, "raaf/dsl/service"
    
    # Pipeline DSL for elegant agent chaining
    autoload :Pipeline, "raaf/dsl/pipeline_dsl/pipeline"
    require_relative "raaf/dsl/pipeline_dsl"

    # Schema generation and caching system
    autoload :Types, "raaf/dsl/types"
    autoload :SchemaBuilder, "raaf/dsl/schema_builder"
    autoload :SchemaGenerator, "raaf/dsl/schema_generator"
    autoload :SchemaCache, "raaf/dsl/schema_cache"

    module Schema
      autoload :SchemaGenerator, "raaf/dsl/schema/schema_generator"
      autoload :SchemaCache, "raaf/dsl/schema/schema_cache"
    end

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
      autoload :ClassResolver, "raaf/dsl/prompts/class_resolver"
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
    #   class MyAgent < RAAF::DSL::Agent
    #     uses_tool :web_search
    #   end
    #
    module Tools
      autoload :Base, "raaf/dsl/tools/base"
      autoload :ConventionOverConfiguration, "raaf/dsl/tools/convention_over_configuration"
      autoload :PerformanceOptimizer, "raaf/dsl/tools/performance_optimizer"
      autoload :Tool, "raaf/dsl/tools/tool"
      autoload :ToolRegistry, "raaf/dsl/tools/tool_registry"
      autoload :WebSearch, "raaf/dsl/tools/web_search"
      autoload :WebSearchPresets, "raaf/dsl/tools/web_search_presets"
      # TavilySearch and PerplexitySearch wrappers removed - use core tools with interceptor
    end

    # Resilience patterns for error handling and retries
    #
    # This module contains resilience patterns and utilities for handling
    # failures, implementing retries with backoff, circuit breakers, and
    # other error handling strategies.
    #
    module Resilience
      autoload :SmartRetry, "raaf/dsl/resilience/smart_retry"
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
    #   class MyAgent < RAAF::DSL::Agent
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
      @prompt_resolvers ||= begin
        registry = PromptResolverRegistry.new
        # Initialize default resolvers immediately to support eager loading
        initialize_default_resolvers(registry)
        registry
      end
    end

    # Force initialization of prompt resolvers for eager loading environments
    #
    # This method is called by the Railtie to ensure resolvers are available
    # when classes are eager loaded in production environments
    #
    # @return [PromptResolverRegistry] The initialized registry
    def self.ensure_prompt_resolvers_initialized!
      # Force initialization by calling the getter
      prompt_resolvers
      
      # Verify resolvers are properly registered
      if @prompt_resolvers.nil? || @prompt_resolvers.resolvers.empty?
        # Fallback initialization if something went wrong
        @prompt_resolvers = PromptResolverRegistry.new
        initialize_default_resolvers(@prompt_resolvers)
      end
      
      @prompt_resolvers
    end

    # Initialize default prompt resolvers
    #
    # @param registry [PromptResolverRegistry] The registry to populate with default resolvers
    # @private
    def self.initialize_default_resolvers(registry)
      # Load resolver classes
      require_relative "raaf/dsl/prompts/class_resolver"
      require_relative "raaf/dsl/prompts/file_resolver"
      
      # Create and register default resolvers
      class_resolver = PromptResolvers::ClassResolver.new(priority: 100)
      file_resolver = PromptResolvers::FileResolver.new(
        priority: 50, 
        paths: ["app/ai/prompts", "prompts"]
      )
      
      registry.register(class_resolver)
      registry.register(file_resolver)
    end
    private_class_method :initialize_default_resolvers

    # Eager load all autoloadable constants for Rails production mode
    #
    # Rails expects modules added to eager_load_namespaces to implement this method.
    # This method triggers loading of all autoloaded constants in the RAAF::DSL module
    # to ensure they are available in production.
    #
    # @return [void]
    def self.eager_load!
      # Load all autoloaded constants in RAAF::DSL
      constants.each do |const_name|
        next if const_name == :Pipeline # Skip problematic constants
        
        begin
          const = const_get(const_name)
          # Recursively eager load nested modules that also support eager loading
          if const.is_a?(Module) && const.respond_to?(:eager_load!)
            const.eager_load!
          end
        rescue NameError, LoadError => e
          # Log any errors but don't fail the entire eager loading process
          # Use basic warn instead of Rails.logger since logger may not be available during initialization
          warn "RAAF::DSL eager loading warning for #{const_name}: #{e.message}"
        end
      end
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
