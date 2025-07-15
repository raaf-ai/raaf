# frozen_string_literal: true

require_relative "raaf/version"

##
# Ruby AI Agents Factory (RAAF) - Main Entry Point
#
# This is the main entry point for the Ruby AI Agents Factory gem.
# It loads all the core components and subgems to provide a comprehensive
# AI agent framework.
#
# @example Basic usage
#   require 'raaf'
#   
#   # Create an agent
#   agent = RubyAIAgentsFactory::Agent.new(
#     name: "Assistant",
#     instructions: "You are a helpful assistant.",
#     model: "gpt-4o"
#   )
#   
#   # Run the agent
#   runner = RubyAIAgentsFactory::Runner.new(agent: agent)
#   result = runner.run("Hello, how are you?")
#   puts result.messages.last[:content]
#
# @example With tools
#   require 'raaf'
#   
#   # Define a custom tool
#   def get_weather(location)
#     "The weather in #{location} is sunny and 72°F"
#   end
#   
#   # Create agent with tools
#   agent = RubyAIAgentsFactory::Agent.new(
#     name: "WeatherBot",
#     instructions: "You are a weather assistant.",
#     model: "gpt-4o",
#     tools: [method(:get_weather)]
#   )
#   
#   runner = RubyAIAgentsFactory::Runner.new(agent: agent)
#   result = runner.run("What's the weather in Tokyo?")
#
# @example With tracing
#   require 'raaf'
#   
#   # Set up tracing
#   tracer = RubyAIAgentsFactory::Tracing::SpanTracer.new
#   tracer.add_processor(RubyAIAgentsFactory::Tracing::OpenAIProcessor.new)
#   
#   # Create agent with tracing
#   agent = RubyAIAgentsFactory::Agent.new(
#     name: "TracedAgent",
#     instructions: "You are a helpful assistant.",
#     model: "gpt-4o"
#   )
#   
#   runner = RubyAIAgentsFactory::Runner.new(agent: agent, tracer: tracer)
#   result = runner.run("Explain quantum computing")
#
# @author Bert Hajee
# @since 0.1.0
#
module RubyAIAgentsFactory
  ##
  # Main configuration class for RAAF
  #
  # Provides global configuration options for the entire framework.
  #
  class Configuration
    attr_accessor :default_model, :default_provider, :log_level, :tracing_enabled

    def initialize
      @default_model = "gpt-4o"
      @default_provider = :responses
      @log_level = :info
      @tracing_enabled = false
    end
  end

  ##
  # Global configuration instance
  #
  # @return [Configuration] The global configuration object
  #
  def self.configuration
    @configuration ||= Configuration.new
  end

  ##
  # Configure RAAF globally
  #
  # @yield [Configuration] The configuration object
  #
  # @example
  #   RubyAIAgentsFactory.configure do |config|
  #     config.default_model = "gpt-4o"
  #     config.tracing_enabled = true
  #   end
  #
  def self.configure
    yield(configuration)
  end

  ##
  # Get the current version
  #
  # @return [String] The current version of RAAF
  #
  def self.version
    VERSION
  end
end

# Load all core components
begin
  # Core framework (required)
  require "raaf-core"
  
  # Providers (required)
  require "raaf-providers"
  
  # Tools (required)
  require "raaf-tools-basic"
  require "raaf-tools-advanced"
  
  # Guardrails (required)
  require "raaf-guardrails"
  
  # Tracing (required)
  require "raaf-tracing"
  
  # Streaming (required)
  require "raaf-streaming"
  
  # Memory (required)
  require "raaf-memory"
  
  # Extensions (required)
  require "raaf-extensions"
  
  # DSL (required)
  require "raaf-dsl"
  
  # Debug tools (required)
  require "raaf-debug"
  
  # Testing utilities (required)
  require "raaf-testing"
  
  # Visualization (required)
  require "raaf-visualization"
  
  # Compliance (required)
  require "raaf-compliance"
  
  # Rails integration (optional - only if Rails is present)
  if defined?(Rails)
    require "raaf-rails"
  end
  
rescue LoadError => e
  # Graceful handling of missing subgems
  warn "RAAF Warning: Some subgems are not available: #{e.message}"
  warn "Please ensure all RAAF subgems are installed or install the complete bundle."
end

# Set up logging
RubyAIAgentsFactory::Logging.configure do |config|
  config.log_level = RubyAIAgentsFactory.configuration.log_level
  config.log_format = :text
  config.log_output = :auto
end

# Log successful initialization
RubyAIAgentsFactory::Logging.info("RAAF initialized successfully", version: RubyAIAgentsFactory::VERSION)