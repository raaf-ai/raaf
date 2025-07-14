# frozen_string_literal: true

require "rails"
require_relative "../logging"

module OpenAIAgents
  module Tracing
    # Rails mountable engine for OpenAI Agents tracing
    #
    # This engine provides a complete web interface for viewing and analyzing
    # OpenAI agent traces stored in a Rails database. It includes:
    #
    # - Database models for traces and spans
    # - Web interface for visualization
    # - Performance analytics dashboard
    # - Cost and usage tracking
    # - Error analysis and monitoring
    #
    # ## Installation
    #
    # 1. Add to your Rails application routes:
    #    mount OpenAIAgents::Tracing::Engine => '/tracing'
    #
    # 2. Run the generator:
    #    rails generate openai_agents:tracing:install
    #
    # 3. Run migrations:
    #    rails db:migrate
    #
    # 4. Configure tracing in an initializer:
    #    OpenAIAgents.tracer.add_processor(
    #      OpenAIAgents::Tracing::ActiveRecordProcessor.new
    #    )
    #
    # ## Usage
    #
    # Visit /tracing in your Rails app to view traces and spans.
    class Engine < ::Rails::Engine
      include OpenAIAgents::Logger
      isolate_namespace OpenAIAgents::Tracing

      # Set the root path for the engine
      config.root = File.expand_path("../../..", __dir__)

      config.generators do |g|
        g.test_framework :rspec
        g.assets true
        g.helper true
        g.stylesheets true
        g.javascripts true
      end

      # Auto-configuration for tracing processor
      config.openai_agents_tracing = ActiveSupport::OrderedOptions.new
      config.openai_agents_tracing.auto_configure = false
      config.openai_agents_tracing.mount_path = "/tracing"
      config.openai_agents_tracing.retention_days = 30
      config.openai_agents_tracing.sampling_rate = 1.0

      initializer "openai_agents.tracing.inflections", before: :load_config_initializers do
        ActiveSupport::Inflector.inflections(:en) do |inflect|
          inflect.acronym "OpenAI"
        end
      end

      initializer "openai_agents.tracing.load_app" do |app|
        # Ensure engine's app directories are loaded
        engine_root = File.expand_path("../../..", __dir__)
        app.config.eager_load_paths += ["#{engine_root}/app/controllers", "#{engine_root}/app/models"]
        app.config.autoload_paths += ["#{engine_root}/app/controllers", "#{engine_root}/app/models"]
      end

      initializer "openai_agents.tracing.configure" do |app|
        # Store config for later access
        OpenAIAgents::Tracing.configuration = app.config.openai_agents_tracing

        # Auto-configure processor if enabled
        if app.config.openai_agents_tracing.auto_configure
          Rails.application.config.after_initialize do
            processor = OpenAIAgents::Tracing::ActiveRecordProcessor.new
            OpenAIAgents.tracer.add_processor(processor)
            OpenAIAgents::Logging.info("Auto-configured ActiveRecord processor")
          rescue StandardError => e
            OpenAIAgents::Logging.warn("Failed to auto-configure", error: e.message, error_class: e.class.name)
          end
        end
      end

      initializer "openai_agents.tracing.assets" do |app|
        # Add engine assets to asset pipeline
        if app.config.respond_to?(:assets)
          app.config.assets.precompile += %w[openai_agents/tracing/application.css openai_agents/tracing/application.js]
        end
      end

      # Set up engine paths
      config.paths.add "app/models", with: "app/models", eager_load: true
      config.paths.add "app/controllers", with: "app/controllers", eager_load: true
      config.paths.add "app/views", with: "app/views"
      config.paths.add "app/helpers", with: "app/helpers", eager_load: true
      config.paths.add "config/routes.rb", with: "config/routes.rb"

      # Load engine-specific configuration
      config.autoload_paths += %W[
        #{root}/app/models/concerns
        #{root}/app/controllers/concerns
        #{root}/lib
      ]
    end

    # Configuration class for the tracing engine
    class Configuration
      attr_accessor :auto_configure, :mount_path, :retention_days, :sampling_rate

      def initialize
        @auto_configure = false
        @mount_path = "/tracing"
        @retention_days = 30
        @sampling_rate = 1.0
      end
    end

    # Global configuration accessor
    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration) if block_given?
      end
    end
  end
end
