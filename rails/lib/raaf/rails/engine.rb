# frozen_string_literal: true

module RAAF
  module Rails
    ##
    # Rails engine for Ruby AI Agents Factory
    #
    # This engine provides a complete Rails integration for RAAF, including:
    # - Mountable routes for dashboard and API
    # - Asset pipeline integration
    # - Middleware setup for authentication and monitoring
    # - WebSocket support via Action Cable
    # - Background job processing with Sidekiq
    # - Automatic helper inclusion in controllers and views
    #
    # @example Mount the engine in your routes
    #   Rails.application.routes.draw do
    #     mount RAAF::Rails::Engine, at: "/agents"
    #   end
    #
    # @example Access engine routes
    #   # Dashboard: /agents/dashboard
    #   # API: /agents/api/v1
    #   # WebSocket: /agents/cable
    #
    # @see RAAF::Rails.configure for configuration options
    #
    class Engine < ::Rails::Engine
      isolate_namespace RAAF::Rails

      # Configure engine paths
      config.autoload_paths << File.expand_path("../../../app", __dir__)
      config.eager_load_paths << File.expand_path("../../../app", __dir__)

      # Set up asset pipeline
      config.assets.enabled = true
      config.assets.paths << File.expand_path("../../../app/assets", __dir__)
      config.assets.precompile += %w[raaf-rails.css raaf-rails.js]

      # Configure generators
      config.generators do |g|
        g.test_framework :rspec, fixture: false
        g.fixture_replacement :factory_bot, dir: "spec/factories"
        g.assets false
        g.helper false
      end

      # Initialize the engine
      initializer "raaf-rails.initialize" do |app|
        # Configure CORS if needed
        if defined?(Rack::Cors)
          app.config.middleware.insert_before 0, Rack::Cors do
            allow do
              origins(*RAAF::Rails.config[:allowed_origins])
              resource "/api/v1/*",
                       headers: :any,
                       methods: %i[get post put patch delete options head]
            end
          end
        end

        # Setup background jobs
        if RAAF::Rails.config[:enable_background_jobs]
          begin
            require "sidekiq"
            Sidekiq.configure_server do |config|
              config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379") }
            end
            Sidekiq.configure_client do |config|
              config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379") }
            end
          rescue LoadError
            # Sidekiq not available, skip background job configuration
            RAAF::Logging.warn("Sidekiq gem not available. Background jobs will be disabled.")
          end
        end

        # Setup WebSocket support
        if RAAF::Rails.config[:enable_websockets]
          begin
            require "action_cable"
            # Modern WebSocket support through Action Cable
            # Configuration will be handled by Rails application
          rescue LoadError
            RAAF::Logging.warn("Action Cable not available. WebSocket support will be disabled.")
          end
        end

        # Setup monitoring
        if RAAF::Rails.config[:monitoring][:enabled]
          begin
            require "raaf-tracing"
            tracer = RAAF::Tracing.create_tracer
            app.config.raaf_tracer = tracer
          rescue LoadError
            RAAF::Logging.warn("raaf-tracing gem not available. Monitoring will be disabled.")
          end
        end

        # Setup authentication
        case RAAF::Rails.config[:authentication_method]
        when :devise
          require "devise"
        when :doorkeeper
          require "doorkeeper"
        end
      end

      # Setup routes - defer to avoid Devise initialization conflicts
      config.after_initialize do
        RAAF::Rails::Engine.routes.draw do
          root "dashboard#index"

          # Dashboard routes
          get "/dashboard", to: "dashboard#index"
          get "/dashboard/agents", to: "dashboard#agents"
          get "/dashboard/conversations", to: "dashboard#conversations"
          get "/dashboard/analytics", to: "dashboard#analytics"

          # Agent management routes
          resources :agents do
            member do
              get :chat
              post :test
              patch :deploy
              delete :undeploy
            end

            resources :conversations, only: %i[index show create]
          end

          # API routes
          namespace :api do
            namespace :v1 do
              resources :agents, only: %i[index show create update destroy] do
                member do
                  post :chat
                  get :status
                  post :deploy
                  delete :undeploy
                end

                resources :conversations, only: %i[index show create]
              end
            end
          end

          # WebSocket routes - Action Cable handles WebSocket connections
          mount ActionCable.server => "/cable" if RAAF::Rails.config[:enable_websockets]
        end
      end

      # Setup middleware
      initializer "raaf-rails.middleware" do |app|
        # Rate limiting middleware
        # if RAAF::Rails.config[:rate_limit][:enabled]
        #   app.config.middleware.use(
        #     RAAF::Rails::Middleware::RateLimitMiddleware
        #   )
        # end

        # Monitoring middleware
        # if RAAF::Rails.config[:monitoring][:enabled]
        #   app.config.middleware.use(
        #     RAAF::Rails::Middleware::MonitoringMiddleware
        #   )
        # end
      end

      # Setup authentication middleware after Rails is ready
      config.to_prepare do
        # if RAAF::Rails.config[:authentication_method] == :devise
        #   if defined?(Devise) && defined?(Warden)
        #     Rails.application.config.middleware.use(
        #       RAAF::Rails::Middleware::AuthenticationMiddleware
        #     )
        #   end
        # else
        #   # Non-Devise authentication
        #   Rails.application.config.middleware.use(
        #     RAAF::Rails::Middleware::AuthenticationMiddleware
        #   )
        # end
      end

      # Setup ActiveRecord models
      initializer "raaf-rails.active_record" do
        if defined?(ActiveRecord)
          ActiveSupport.on_load(:active_record) do
            # include RAAF::Rails::Models::AgentModel
            # include RAAF::Rails::Models::ConversationModel
            # include RAAF::Rails::Models::MessageModel
          end
        end
      end

      # Setup ActionController
      initializer "raaf-rails.action_controller" do
        if defined?(ActionController)
          ActiveSupport.on_load(:action_controller) do
            include RAAF::Rails::Helpers::AgentHelper
          end
        end
      end

      # Setup ActionView
      initializer "raaf-rails.action_view" do
        if defined?(ActionView)
          ActiveSupport.on_load(:action_view) do
            include RAAF::Rails::Helpers::AgentHelper
          end
        end
      end

      # Setup logging
      initializer "raaf-rails.logging" do
        if defined?(::Rails.logger)
          RAAF::Logging.configure do |config|
            config.log_output = :rails
          end
        end
      end

      # Setup I18n
      initializer "raaf-rails.i18n" do
        config.i18n.load_path += Dir[
          File.expand_path("../../../config/locales/*.yml", __dir__)
        ]
      end

      # Setup assets
      initializer "raaf-rails.assets" do
        if defined?(Sprockets)
          config.assets.paths << File.expand_path("../../../app/assets/stylesheets", __dir__)
          config.assets.paths << File.expand_path("../../../app/assets/javascripts", __dir__)
          config.assets.paths << File.expand_path("../../../app/assets/images", __dir__)
        end
      end
    end
  end
end
