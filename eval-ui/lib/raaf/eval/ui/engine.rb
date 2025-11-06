# frozen_string_literal: true

require "rails"
require "turbo-rails"
require "stimulus-rails"
require "phlex-rails"

module RAAF
  module Eval
    module UI
      ##
      # Rails engine for RAAF Eval UI
      #
      # Provides a mountable web interface for interactive agent evaluation,
      # including span browsing, prompt editing, evaluation execution, and
      # results comparison.
      #
      # @example Mount in routes
      #   Rails.application.routes.draw do
      #     mount RAAF::Eval::UI::Engine, at: "/eval"
      #   end
      #
      class Engine < ::Rails::Engine
        isolate_namespace RAAF::Eval::UI

        # Configure engine paths
        config.autoload_paths << root.join("app/models")
        config.autoload_paths << root.join("app/controllers")
        config.autoload_paths << root.join("app/components")
        config.autoload_paths << root.join("app/jobs")

        config.eager_load_paths << root.join("app/models")
        config.eager_load_paths << root.join("app/controllers")
        config.eager_load_paths << root.join("app/components")
        config.eager_load_paths << root.join("app/jobs")

        # Set up asset pipeline
        config.assets.enabled = true if defined?(Sprockets)
        config.assets.paths << root.join("app/assets/stylesheets")
        config.assets.paths << root.join("app/assets/javascripts")
        config.assets.precompile += %w[raaf/eval/ui/application.css raaf/eval/ui/application.js]

        # Configure generators
        config.generators do |g|
          g.test_framework :rspec, fixture: false
          g.fixture_replacement :factory_bot, dir: "spec/factories"
          g.assets false
          g.helper false
        end

        # Ensure migrations are available
        initializer "raaf-eval-ui.migrations" do |app|
          unless app.root.to_s.match?(root.to_s)
            config.paths["db/migrate"].expanded.each do |expanded_path|
              app.config.paths["db/migrate"] << expanded_path
            end
          end
        end

        # Register RAAF as an acronym for proper constant loading
        initializer "raaf-eval-ui.inflections", before: :load_config_initializers do
          ActiveSupport::Inflector.inflections(:en) do |inflect|
            inflect.acronym "RAAF"
            inflect.acronym "UI"
          end
        end

        # Setup Stimulus controllers
        initializer "raaf-eval-ui.importmap", before: "importmap" do |app|
          if defined?(Importmap)
            # Pin Stimulus controllers from this engine
            app.config.importmap.cache_sweepers << root.join("app/assets/javascripts")
          end
        end

        # Setup Phlex components
        initializer "raaf-eval-ui.phlex" do
          if defined?(Phlex)
            # Phlex components are automatically loaded via autoload_paths
          end
        end

        # Setup ActiveJob queue
        initializer "raaf-eval-ui.active_job" do
          if defined?(ActiveJob)
            # Define queue for evaluation jobs
            ActiveJob::Base.queue_name_prefix = "raaf_eval_ui"
          end
        end
      end
    end
  end
end
