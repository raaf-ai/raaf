# frozen_string_literal: true

require "yaml"
require "psych"
require "pathname"
require "active_support/core_ext/hash/indifferent_access"
require "active_support/core_ext/string/inflections"

# AI Agent DSL Configuration Management
#
# A comprehensive configuration system for AI agents that supports:
# - Environment-specific configurations (development, test, production)
# - Agent-specific overrides and settings
# - Global defaults with inheritance
# - Cost optimization through environment-aware model selection
# - Graceful fallbacks and error handling
# - Rails integration with automatic path detection
#
# The configuration system loads YAML files and provides a hierarchical
# configuration resolution:
# 1. Global defaults (applies to all agents)
# 2. Environment-specific global settings
# 3. Agent-specific overrides
#
# @example Basic configuration file (config/ai_agents.yml)
#   defaults:
#     global:
#       model: "gpt-4o"
#       max_turns: 3
#       temperature: 0.7
#
#   development:
#     global:
#       model: "gpt-4o-mini"  # Cheaper model for development
#       max_turns: 2
#     agents:
#       market_research_agent:
#         max_turns: 1       # Even fewer turns for this specific agent
#
#   production:
#     global:
#       model: "gpt-4o"
#       max_turns: 5
#       timeout: 180
#
# @example Using configuration in agents
#   class MarketResearchAgent < AiAgentDsl::Agents::Base
#     include AiAgentDsl::AgentDsl
#
#     # Configuration is automatically loaded based on agent name
#     agent_name "market_research_agent"
#   end
#
# @example Manual configuration access
#   # Get configuration for specific agent
#   config = AiAgentDsl::Config.for_agent("market_research_agent")
#
#   # Get model for agent in current environment
#   model = AiAgentDsl::Config.model_for("market_research_agent")
#
#   # Get global configuration
#   global_config = AiAgentDsl::Config.global
#
# @see AiAgentDsl::AgentDsl For automatic configuration integration
# @since 0.1.0
#
class AiAgentDsl::Config
  class << self
    # Get configuration for a specific agent
    def for_agent(agent_name, environment: current_environment)
      agent_key = normalize_agent_name(agent_name)

      # Try agent-specific config first, fall back to global
      agent_config = environment_config(environment).dig("agents", agent_key) || {}
      global_config = environment_config(environment)["global"] || {}

      # Merge global defaults with agent-specific overrides
      global_config.merge(agent_config).with_indifferent_access
    end

    # Get global configuration for current environment
    def global(environment: current_environment)
      environment_config(environment)["global"] || {}
    end

    # Get max_turns for a specific agent
    def max_turns_for(agent_name, environment: current_environment)
      for_agent(agent_name, environment: environment)["max_turns"] ||
        AiAgentDsl.configuration.default_max_turns
    end

    # Get model for a specific agent
    def model_for(agent_name, environment: current_environment)
      for_agent(agent_name, environment: environment)["model"] ||
        AiAgentDsl.configuration.default_model
    end

    # Get temperature for a specific agent
    def temperature_for(agent_name, environment: current_environment)
      for_agent(agent_name, environment: environment)["temperature"] ||
        AiAgentDsl.configuration.default_temperature
    end

    # Get timeout for a specific agent
    def timeout_for(agent_name, environment: current_environment)
      for_agent(agent_name, environment: environment)["timeout"] || 120
    end

    # Get tool choice for a specific agent
    #
    # Returns the configured tool choice behavior for the specified agent.
    # Tool choice controls how the AI model selects and uses tools during execution.
    #
    # @param agent_name [String] The name of the agent
    # @param environment [String] The environment to check (defaults to current)
    # @return [String, Hash, nil] The tool choice configuration, or nil if not configured
    #
    # @example YAML configuration
    #   # config/ai_agents.yml
    #   production:
    #     global:
    #       tool_choice: "auto"
    #     agents:
    #       research_agent:
    #         tool_choice: "required"
    #       analysis_agent:
    #         tool_choice: { type: "function", function: { name: "web_search" } }
    #
    def tool_choice_for(agent_name, environment: current_environment)
      for_agent(agent_name, environment: environment)["tool_choice"]
    end

    # Get all agent configurations for current environment
    def all_agents(environment: current_environment)
      environment_config(environment)["agents"] || {}
    end

    # Check if agent is configured
    def agent_configured?(agent_name, environment: current_environment)
      agent_key = normalize_agent_name(agent_name)
      all_agents(environment: environment).key?(agent_key)
    end

    # Reload configuration (useful for development)
    def reload!
      @config = nil
      @environment_configs = {}
      load_config
    end

    # Get raw configuration hash
    def raw_config
      @raw_config ||= load_config
    end

    # Get current environment (Rails-aware but works without Rails)
    def current_environment
      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env
      else
        ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
      end
    end

    private

    # Load configuration from YAML file
    def load_config
      config_path = if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
                      Rails.root.join("config", "ai_agents.yml")
                    else
                      config_file = AiAgentDsl.configuration.config_file
                      # If config_file is already an absolute path, use it as-is
                      # Otherwise, join it with the current working directory
                      Pathname.new(config_file).absolute? ? config_file : File.join(Dir.pwd, config_file)
                    end

      unless File.exist?(config_path)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn "AI agents configuration file not found: #{config_path}"
        end
        return {}
      end

      begin
        YAML.load_file(config_path, aliases: true) || {}
      rescue Psych::SyntaxError => e
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error "Invalid YAML in AI agents configuration: #{e.message}"
        end
        {}
      rescue StandardError => e
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error "Error loading AI agents configuration: #{e.message}"
        end
        {}
      end
    end

    # Get configuration for specific environment
    def environment_config(environment)
      @environment_configs ||= {}
      @environment_configs[environment.to_s] ||= begin
        env_config = raw_config[environment.to_s] || {}
        defaults = raw_config["defaults"] || {}

        # Always merge defaults first, then layer environment-specific config on top
        if env_config.empty?
          defaults
        else
          defaults.deep_merge(env_config)
        end
      end
    end

    # Normalize agent name for YAML lookup
    # E.g., "MarketResearchAgent" -> "market_research_agent"
    # E.g., "ProspectDiscoveryOrchestrator" -> "prospect_discovery_orchestrator"
    def normalize_agent_name(agent_name)
      agent_name.to_s.underscore
    end
  end

  # Instance methods for backward compatibility
  def initialize(environment: self.class.send(:current_environment))
    @environment = environment
  end

  def for_agent(agent_name)
    self.class.for_agent(agent_name, environment: @environment)
  end

  def global
    self.class.global(environment: @environment)
  end

  def max_turns_for(agent_name)
    self.class.max_turns_for(agent_name, environment: @environment)
  end

  def model_for(agent_name)
    self.class.model_for(agent_name, environment: @environment)
  end

  def temperature_for(agent_name)
    self.class.temperature_for(agent_name, environment: @environment)
  end

  def tool_choice_for(agent_name)
    self.class.tool_choice_for(agent_name, environment: @environment)
  end

  private

  attr_reader :environment
end
