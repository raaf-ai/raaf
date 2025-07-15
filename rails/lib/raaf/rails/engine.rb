# frozen_string_literal: true

module RubyAIAgentsFactory
  module Rails
    ##
    # Rails engine for Ruby AI Agents Factory
    #
    # Provides mountable Rails engine with dashboard, API endpoints,
    # and WebSocket support for AI agent management.
    #
    class Engine < ::Rails::Engine
      isolate_namespace RubyAIAgentsFactory::Rails

      # Configure engine paths
      config.autoload_paths << File.expand_path("../../../../app", __FILE__)
      config.eager_load_paths << File.expand_path("../../../../app", __FILE__)

      # Set up asset pipeline
      config.assets.enabled = true
      config.assets.paths << File.expand_path("../../../../app/assets", __FILE__)
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
              origins(*RubyAIAgentsFactory::Rails.config[:allowed_origins])
              resource "/api/v1/*",
                headers: :any,
                methods: [:get, :post, :put, :patch, :delete, :options, :head]
            end
          end
        end

        # Setup background jobs
        if RubyAIAgentsFactory::Rails.config[:enable_background_jobs]
          require "sidekiq"
          Sidekiq.configure_server do |config|
            config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379") }
          end
          Sidekiq.configure_client do |config|
            config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379") }
          end
        end

        # Setup WebSocket support
        if RubyAIAgentsFactory::Rails.config[:enable_websockets]
          require "websocket-rails"
          WebsocketRails.setup do |config|
            config.log_level = :debug
            config.auto_reconnect = true
          end
        end

        # Setup monitoring
        if RubyAIAgentsFactory::Rails.config[:monitoring][:enabled]
          require "raaf-tracing"
          tracer = RubyAIAgentsFactory::Tracing.create_tracer
          app.config.raaf_tracer = tracer
        end

        # Setup authentication
        case RubyAIAgentsFactory::Rails.config[:authentication_method]
        when :devise
          require "devise"
        when :doorkeeper
          require "doorkeeper"
        end
      end

      # Setup routes
      initializer "raaf-rails.routes" do
        RubyAIAgentsFactory::Rails::Engine.routes.draw do
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
            
            resources :conversations, only: [:index, :show, :create]
          end

          # API routes
          namespace :api do
            namespace :v1 do
              resources :agents, only: [:index, :show, :create, :update, :destroy] do
                member do
                  post :chat
                  get :status
                  post :deploy
                  delete :undeploy
                end
                
                resources :conversations, only: [:index, :show, :create]
              end
            end
          end

          # WebSocket routes
          if RubyAIAgentsFactory::Rails.config[:enable_websockets]
            websocket "/chat", to: "websocket#connect"
          end
        end
      end

      # Setup middleware
      initializer "raaf-rails.middleware" do |app|
        # Rate limiting middleware
        if RubyAIAgentsFactory::Rails.config[:rate_limit][:enabled]
          app.config.middleware.use(
            RubyAIAgentsFactory::Rails::Middleware::RateLimitMiddleware
          )
        end

        # Authentication middleware
        app.config.middleware.use(
          RubyAIAgentsFactory::Rails::Middleware::AuthenticationMiddleware
        )

        # Monitoring middleware
        if RubyAIAgentsFactory::Rails.config[:monitoring][:enabled]
          app.config.middleware.use(
            RubyAIAgentsFactory::Rails::Middleware::MonitoringMiddleware
          )
        end
      end

      # Setup ActiveRecord models
      initializer "raaf-rails.active_record" do
        if defined?(ActiveRecord)
          ActiveSupport.on_load(:active_record) do
            include RubyAIAgentsFactory::Rails::Models::AgentModel
            include RubyAIAgentsFactory::Rails::Models::ConversationModel
            include RubyAIAgentsFactory::Rails::Models::MessageModel
          end
        end
      end

      # Setup ActionController
      initializer "raaf-rails.action_controller" do
        if defined?(ActionController)
          ActiveSupport.on_load(:action_controller) do
            include RubyAIAgentsFactory::Rails::Helpers::AgentHelper
          end
        end
      end

      # Setup ActionView
      initializer "raaf-rails.action_view" do
        if defined?(ActionView)
          ActiveSupport.on_load(:action_view) do
            include RubyAIAgentsFactory::Rails::Helpers::AgentHelper
          end
        end
      end

      # Setup logging
      initializer "raaf-rails.logging" do
        if defined?(::Rails.logger)
          RubyAIAgentsFactory::Logging.configure do |config|
            config.log_output = :rails
          end
        end
      end

      # Setup I18n
      initializer "raaf-rails.i18n" do
        config.i18n.load_path += Dir[
          File.expand_path("../../../../config/locales/*.yml", __FILE__)
        ]
      end

      # Setup assets
      initializer "raaf-rails.assets" do
        if defined?(Sprockets)
          config.assets.paths << File.expand_path("../../../../app/assets/stylesheets", __FILE__)
          config.assets.paths << File.expand_path("../../../../app/assets/javascripts", __FILE__)
          config.assets.paths << File.expand_path("../../../../app/assets/images", __FILE__)
        end
      end
    end
  end
end