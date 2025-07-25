# frozen_string_literal: true

require_relative "raaf/rails/version"
require_relative "raaf/rails/engine"
# require_relative "raaf/rails/websocket_handler" # Disabled - requires websocket-rails
# require_relative "raaf/rails/configuration"
# require_relative "raaf/rails/authenticator"
# require_relative "raaf/rails/middleware"
# require_relative "raaf/rails/controllers/base_controller"
# require_relative "raaf/rails/controllers/agents_controller"
# require_relative "raaf/rails/controllers/conversations_controller"
# require_relative "raaf/rails/controllers/dashboard_controller"
# require_relative "raaf/rails/controllers/api/v1/agents_controller"
# require_relative "raaf/rails/jobs/agent_job"
# require_relative "raaf/rails/jobs/conversation_job"
# require_relative "raaf/rails/models/agent_model"
# require_relative "raaf/rails/models/conversation_model"
# require_relative "raaf/rails/models/message_model"
require_relative "raaf/rails/helpers/agent_helper"

module RAAF
  ##
  # Rails integration and web interface for Ruby AI Agents Factory
  #
  # The Rails module provides comprehensive Rails integration including:
  # - Web-based dashboard for managing agents
  # - REST API for agent interactions
  # - Real-time conversation interface
  # - Authentication and authorization
  # - Background job processing
  # - Monitoring and analytics
  # - Deployment tools
  #
  # @example Basic Rails integration
  #   # In your Rails application
  #   gem 'raaf-rails'
  #   
  #   # Mount the engine in config/routes.rb
  #   mount RAAF::Rails::Engine, at: "/agents"
  #   
  #   # Configure in config/initializers/raaf.rb
  #   RAAF::Rails.configure do |config|
  #     config.authentication_method = :devise
  #     config.enable_dashboard = true
  #     config.enable_api = true
  #   end
  #
  # @example Agent creation via Rails
  #   # In a Rails controller
  #   class AgentsController < ApplicationController
  #     def create
  #       @agent = RAAF::Rails::AgentModel.create!(
  #         name: params[:name],
  #         instructions: params[:instructions],
  #         model: params[:model],
  #         user: current_user
  #       )
  #       
  #       redirect_to agent_path(@agent)
  #     end
  #   end
  #
  # @example API usage
  #   # POST /api/v1/agents/:id/conversations
  #   {
  #     "message": "Hello, assistant!",
  #     "context": {
  #       "user_id": 123,
  #       "session_id": "abc123"
  #     }
  #   }
  #   
  #   # Response:
  #   {
  #     "id": "conv_456",
  #     "message": "Hello! How can I help you today?",
  #     "usage": {
  #       "input_tokens": 10,
  #       "output_tokens": 8,
  #       "total_tokens": 18
  #     },
  #     "metadata": {
  #       "response_time": 1.25,
  #       "model": "gpt-4o"
  #     }
  #   }
  #
  # @example Real-time conversation
  #   // In JavaScript
  #   const ws = new WebSocket('ws://localhost:3000/agents/chat');
  #   
  #   ws.onmessage = function(event) {
  #     const data = JSON.parse(event.data);
  #     console.log('Assistant:', data.message);
  #   };
  #   
  #   ws.send(JSON.stringify({
  #     type: 'message',
  #     content: 'Hello!',
  #     agent_id: 'agent_123'
  #   }));
  #
  # @since 1.0.0
  module Rails
    # Default configuration
    DEFAULT_CONFIG = {
      authentication_method: :none,
      enable_dashboard: true,
      enable_api: true,
      enable_websockets: true,
      enable_background_jobs: true,
      dashboard_path: "/dashboard",
      api_path: "/api/v1",
      websocket_path: "/chat",
      allowed_origins: ["*"],
      rate_limit: {
        enabled: true,
        requests_per_minute: 60
      },
      monitoring: {
        enabled: true,
        metrics: [:usage, :performance, :errors]
      }
    }.freeze

    class << self
      # @return [Hash] Current Rails configuration
      attr_accessor :config

      ##
      # Configure Rails integration
      #
      # @param options [Hash] Configuration options
      # @option options [Symbol] :authentication_method (:none) Authentication method
      # @option options [Boolean] :enable_dashboard (true) Enable web dashboard
      # @option options [Boolean] :enable_api (true) Enable REST API
      # @option options [Boolean] :enable_websockets (true) Enable WebSocket support
      # @option options [Boolean] :enable_background_jobs (true) Enable background processing
      # @option options [String] :dashboard_path ("/dashboard") Dashboard mount path
      # @option options [String] :api_path ("/api/v1") API mount path
      # @option options [Array] :allowed_origins (["*"]) CORS allowed origins
      #
      # @example Configure Rails integration
      #   RAAF::Rails.configure do |config|
      #     config.authentication_method = :devise
      #     config.enable_dashboard = true
      #     config.enable_api = true
      #     config.allowed_origins = ["https://myapp.com"]
      #   end
      #
      def configure
        @config ||= DEFAULT_CONFIG.dup
        yield @config if block_given?
        @config
      end

      ##
      # Get current configuration
      #
      # @return [Hash] Current configuration
      def config
        @config ||= DEFAULT_CONFIG.dup
      end

      ##
      # Install Rails integration
      #
      # Sets up necessary Rails components including routes, middleware,
      # and initializers for AI agent functionality.
      #
      def install!
        return unless defined?(::Rails)

        install_middleware
        install_routes
        install_initializers
        install_assets
      end

      ##
      # Create a new agent model
      #
      # @param attributes [Hash] Agent attributes
      # @return [AgentModel] New agent model instance
      def create_agent(**attributes)
        AgentModel.create!(**attributes)
      end

      ##
      # Find agent by ID
      #
      # @param id [String] Agent ID
      # @return [AgentModel, nil] Agent model or nil if not found
      def find_agent(id)
        AgentModel.find_by(id: id)
      end

      ##
      # Get all agents for user
      #
      # @param user [Object] User object
      # @return [Array<AgentModel>] Array of agent models
      def agents_for_user(user)
        AgentModel.where(user: user)
      end

      ##
      # Start conversation with agent
      #
      # @param agent_id [String] Agent ID
      # @param message [String] User message
      # @param context [Hash] Conversation context
      # @return [Hash] Conversation result
      def start_conversation(agent_id, message, context = {})
        agent = find_agent(agent_id)
        return nil unless agent

        conversation = ConversationModel.create!(
          agent: agent,
          user: context[:user],
          context: context
        )

        conversation.add_message(message, role: "user")
        response = agent.process_message(message, context)
        conversation.add_message(response[:content], role: "assistant")

        {
          conversation_id: conversation.id,
          message: response[:content],
          usage: response[:usage],
          metadata: response[:metadata]
        }
      end

      private

      def install_middleware
        return unless defined?(::Rails)

        ::Rails.application.config.middleware.use(
          RAAF::Rails::Middleware
        )
      end

      def install_routes
        return unless defined?(::Rails)

        ::Rails.application.routes.draw do
          mount RAAF::Rails::Engine, at: config[:dashboard_path]
          
          if config[:enable_api]
            namespace :api do
              namespace :v1 do
                resources :agents do
                  resources :conversations, only: [:create, :show, :index]
                end
              end
            end
          end

          # if config[:enable_websockets]
          #   mount RAAF::Rails::WebsocketHandler, at: config[:websocket_path]
          # end
        end
      end

      def install_initializers
        return unless defined?(::Rails)

        # Setup background jobs
        if config[:enable_background_jobs] && defined?(Sidekiq)
          require 'sidekiq/web'
          ::Rails.application.routes.draw do
            mount Sidekiq::Web => '/sidekiq'
          end
        end

        # Setup logging integration
        if defined?(::Rails.logger)
          RAAF::Logging.configure do |logging_config|
            logging_config.log_output = :rails
          end
        end
      end

      def install_assets
        return unless defined?(::Rails)

        # Add asset paths
        if ::Rails.application.config.assets
          ::Rails.application.config.assets.paths << 
            File.join(File.dirname(__FILE__), "rails", "assets")
        end
      end
    end
  end
end