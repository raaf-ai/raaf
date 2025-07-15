# frozen_string_literal: true

# Only load Rails generators if we're in a Rails environment
if defined?(Rails::Application) || ENV["RAILS_ENV"] || File.exist?("config/application.rb")
  begin
    require "rails"
    require "rails/generators/actions"
    require "rails/generators/base"
    # Flag indicating whether Rails generator dependencies are available for config generation
    # @api private
    CONFIG_GENERATOR_RAILS_AVAILABLE = true
  rescue LoadError, NameError
    # Flag indicating whether Rails generator dependencies are available for config generation
    # @api private
    CONFIG_GENERATOR_RAILS_AVAILABLE = false
  end
else
  # Flag indicating whether Rails generator dependencies are available for config generation
  # @api private
  CONFIG_GENERATOR_RAILS_AVAILABLE = false
end

# Define minimal interface when Rails is not available
# This provides stub classes that allow the config generator to be loaded and tested
# even when Rails is not available in the environment.
# @api private
unless CONFIG_GENERATOR_RAILS_AVAILABLE
  # Minimal Rails module stub for non-Rails environments (config generator specific)
  # @api private
  module Rails
    # Minimal Generators module stub for config generator
    # @api private
    module Generators
      # Returns empty array when Rails generators are not available
      # @api private
      def self.subclasses
        []
      end

      # Returns nil when Rails generators are not available
      # @api private
      def self.find_by_namespace(_name)
        nil
      end

      # Minimal Base stub for config generator testing without Rails
      # @api private
      class Base
        # Stub implementation for source_root class method
        # @api private
        def self.source_root(path = nil)
          @source_root = path if path
          @source_root
        end

        # Stub implementation for desc class method
        # @api private
        def self.desc(description = nil)
          @desc = description if description
          @desc || "Rails generator"
        end

        # Stub implementation for namespace class method
        # @api private
        def self.namespace(name = nil)
          @namespace = name if name
          @namespace || "ai_agent_dsl:config"
        end

        # Stub implementation for inherited callback
        # @api private
        def self.inherited(subclass)
          # Do nothing to avoid Rails initialization issues
        end

        # Stub implementation for initialize method
        # @api private
        def initialize(*args)
          # Minimal implementation for testing
        end
      end
    end
  end
end

module AiAgentDsl
  module Generators
    # Rails generator for creating AI agent configuration files
    #
    # This generator creates the necessary configuration files to get started
    # with AI Agent DSL in a Rails application. It sets up environment-specific
    # configuration and provides a Rails initializer for custom settings.
    #
    # ## Generated Files
    #
    # ### 1. config/ai_agents.yml
    # The main configuration file containing environment-specific settings for:
    # - **Global Settings**: Default model, max_turns, temperature for all agents
    # - **Environment Overrides**: Different settings for development, test, production
    # - **Agent-Specific Config**: Custom settings for individual agents
    # - **Cost Optimization**: Automatic model switching for cost efficiency
    #
    # ### 2. config/initializers/ai_config.rb
    # A Rails initializer that allows for:
    # - **Custom Configuration**: Override default gem settings
    # - **Runtime Setup**: Configure logging, monitoring, custom adapters
    # - **Environment Detection**: Rails-aware environment handling
    # - **Integration Setup**: Connect with external services or tools
    #
    # ## Configuration Features
    #
    # ### Environment-Aware Configuration
    # - **Development**: Uses cheaper models (gpt-4o-mini) for cost savings
    # - **Test**: Minimal configuration for fast test execution
    # - **Production**: Full-featured configuration optimized for performance
    #
    # ### Cost Optimization
    # The generated configuration includes automatic cost optimization:
    # - Development environments use cheaper models (50-75% cost reduction)
    # - Test environments use single-turn execution (90%+ cost reduction)
    # - Production environments balance cost and performance
    #
    # ### YAML Structure
    # The configuration uses YAML anchors and merging for DRY principles:
    # ```yaml
    # defaults: &defaults
    #   global:
    #     model: "gpt-4o"
    #     max_turns: 3
    #
    # development:
    #   <<: *defaults
    #   global:
    #     model: "gpt-4o-mini"  # Cost optimization
    # ```
    #
    # ## Usage Examples
    #
    # @example Basic configuration generation
    #   rails generate ai_agent_dsl:config
    #   # Creates:
    #   # - config/ai_agents.yml
    #   # - config/initializers/ai_config.rb
    #
    # @example After generation, using the configuration
    #   # In your agent
    #   class MyAgent < AiAgentDsl::Agents::Base
    #     include AiAgentDsl::AgentDsl
    #     agent_name "my_agent"
    #     # Configuration is automatically loaded from YAML
    #   end
    #
    # @example Customizing in the initializer
    #   # config/initializers/ai_config.rb
    #   AiAgentDsl.configure do |config|
    #     config.default_model = "gpt-4o-mini"
    #     config.default_max_turns = 5
    #   end
    #
    # ## File Templates
    # The generator uses ERB templates to create customized configuration
    # based on the Rails application's structure and needs.
    #
    # @see Rails::Generators::Base Rails generator base class
    # @since 0.1.0
    #
    class ConfigGenerator < Rails::Generators::Base
      # Set the template directory for the generator
      # Templates are located in the same directory as this generator file
      source_root File.expand_path("templates", __dir__)

      # Description shown when running 'rails generate --help'
      desc "Generate ai_agents.yml configuration file"

      # Create the main AI agents configuration file
      #
      # This method generates config/ai_agents.yml with environment-specific
      # configuration for AI agents. The file includes:
      #
      # - **Default Settings**: Base configuration shared across environments
      # - **Environment Overrides**: Specific settings for development, test, production
      # - **Cost Optimization**: Automatic model selection for cost efficiency
      # - **Agent-Specific Config**: Examples of per-agent configuration
      # - **YAML Best Practices**: Uses anchors and merging for maintainability
      #
      # The generated file provides a complete starting point with sensible
      # defaults that optimize for both development productivity and production
      # performance while managing API costs effectively.
      #
      # @example Generated file structure
      #   # config/ai_agents.yml
      #   defaults: &defaults
      #     global:
      #       model: "gpt-4o"
      #       max_turns: 3
      #       temperature: 0.7
      #
      #   development:
      #     <<: *defaults
      #     global:
      #       model: "gpt-4o-mini"  # 95% cost reduction
      #       max_turns: 2
      def create_config_file
        template "ai_agents.yml.erb", "config/ai_agents.yml"
      end

      # Create the Rails initializer for AI configuration
      #
      # This method generates config/initializers/ai_config.rb which provides
      # a place for custom configuration that goes beyond what's available
      # in the YAML file. The initializer allows for:
      #
      # - **Gem Configuration**: Setting global defaults and options
      # - **Custom Adapters**: Configuring custom AI service adapters
      # - **Logging Setup**: Integrating with Rails logging and monitoring
      # - **Runtime Configuration**: Dynamic configuration based on environment
      # - **Integration Hooks**: Setting up connections to external services
      #
      # The generated initializer includes examples and documentation for
      # common configuration scenarios.
      #
      # @example Generated initializer content
      #   # config/initializers/ai_config.rb
      #   AiAgentDsl.configure do |config|
      #     config.default_model = "gpt-4o"
      #     config.default_max_turns = 3
      #     config.default_temperature = 0.7
      #   end
      def create_initializer
        template "ai_config.rb.erb", "config/initializers/ai_config.rb"
      end
    end
  end
end
