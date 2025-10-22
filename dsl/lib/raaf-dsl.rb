# frozen_string_literal: true

require "zeitwerk"
require "raaf-core"
require "active_support/all"

# Set up Zeitwerk loader for RAAF DSL
loader = Zeitwerk::Loader.for_gem
loader.tag = "raaf-dsl"

# Configure inflections for acronyms and special cases
loader.inflector.inflect(
  "dsl" => "DSL",
  "llm_interceptor" => "LLMInterceptor",
  "pii" => "PII"
)

# Load version before setup
require_relative "raaf/dsl/core/version"

# Setup the loader
loader.setup

# Load tracing functionality after setup
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
      # Zeitwerk will have already loaded these classes
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
      loader.eager_load
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

# Eager load if requested
loader.eager_load if ENV['RAAF_EAGER_LOAD'] == 'true'
