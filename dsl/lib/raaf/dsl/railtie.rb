# frozen_string_literal: true

require "rails/railtie"

# Rails integration for AI Agent DSL
#
# This railtie automatically configures the gem for Rails applications providing
# seamless integration between the DSL and Rails ecosystem. It handles:
#
# ## Features
# - **Configuration Loading**: Automatically loads config/ai_agents.yml during Rails boot
# - **Generator Integration**: Provides Rails generators for agent and config scaffolding
# - **Environment Detection**: Uses Rails environment for configuration selection
# - **Eager Loading**: Configures proper eager loading for production environments
# - **Initializer Setup**: Sets up proper initialization order and dependencies
#
# ## Configuration Files
# The railtie looks for and manages these files:
# - `config/ai_agents.yml` - Main configuration file with environment-specific settings
# - `config/initializers/ai_config.rb` - Optional Rails initializer for custom configuration
#
# ## Environment Behavior
# - **Development**: Logs initialization messages, reloads config on changes
# - **Production**: Eager loads namespaces, optimizes for performance
# - **Test**: Minimal configuration for fast test execution
#
# ## Generator Integration
# Automatically registers these generators:
# - `rails generate raaf:config` - Creates configuration files
# - `rails generate raaf:agent NAME` - Creates agent and prompt classes
#
# @example Manual railtie loading (if needed)
#   # In config/application.rb
#   require 'raaf/dsl/railtie'
#
# @example Checking if railtie is loaded
#   Rails.application.railties.map(&:class).include?(RAAF::DSL::Railtie)
#
# @see Rails::Railtie Rails railtie documentation
# @since 0.1.0
#
module RAAF
  module DSL
    class Railtie < ::Rails::Railtie
      # Set the railtie name for Rails integration
      # This name is used in Rails configuration and logging
      railtie_name :raaf_dsl

      # Configure the gem when Rails application is being prepared
      #
      # This block runs every time the Rails application is reloaded in development
      # and once during startup in production. It ensures that the AI agent
      # configuration is loaded and available throughout the application lifecycle.
      #
      # @note This runs after all Rails components are loaded but before
      #       the application starts serving requests
      config.to_prepare do
        # Load AI agent configuration from Rails app if the config file exists
        # This allows for hot-reloading of configuration in development
        RAAF::DSL::Config.reload! if ::Rails.root.join("config/ai_agents.yml").exist?
      end

      # Early initialization of AI Agent DSL configuration
      #
      # This initializer runs early in the Rails boot process to set up
      # the gem's configuration before other components may need it.
      # It configures Rails-specific paths.
      #
      # @param app [Rails::Application] The Rails application instance
      initializer "raaf_dsl.configure" do |_app|
        # Set Rails-aware configuration path to use Rails.root instead of Dir.pwd
        # This ensures proper path resolution in all Rails deployment scenarios
        RAAF::DSL.configure do |config|
          config.config_file = ::Rails.root.join("config/ai_agents.yml").to_s
        end
      end

      # Register Rails generators for AI agent scaffolding
      #
      # This block loads and makes available the custom generators provided
      # by the gem. These generators help developers quickly scaffold new
      # agents and configuration files using Rails conventions.
      #
      # Available generators:
      # - AgentGenerator: Creates agent classes and their corresponding prompts
      # - ConfigGenerator: Creates initial configuration files
      generators do
        require "raaf/dsl/generators/agent_generator"
        require "raaf/dsl/generators/config_generator"
      end

      # Configure eager loading for production environments
      #
      # This ensures that all RAAF::DSL classes are loaded at application
      # startup in production, which improves performance and helps catch
      # any loading issues early.
      #
      # @note This is particularly important for AI agent classes that may
      #       be dynamically referenced through configuration
      config.eager_load_namespaces << RAAF::DSL

      # Initialize prompt resolvers after Rails loads in eager-loaded environments
      #
      # In staging/production with config.eager_load = true, Rails loads all classes
      # at boot time. However, RAAF's prompt resolver registry uses lazy initialization
      # which can cause "No resolver could handle the prompt specification" errors.
      # This hook ensures the resolver registry is initialized before any agents run.
      #
      # @note Fixes prompt resolution failures in staging/production environments
      config.after_initialize do
        # Always ensure prompt resolvers are initialized, regardless of environment
        # This provides better reliability across all deployment scenarios
        RAAF::DSL.ensure_prompt_resolvers_initialized!
      rescue StandardError
        # A resolver registry that cannot be built must not stop the app from
        # booting; agents that need one will fail at their own call site.
      end
    end
  end
end
