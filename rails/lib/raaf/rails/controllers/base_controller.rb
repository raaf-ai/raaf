# frozen_string_literal: true

module RAAF
  module Rails
    module Controllers
      ##
      # Base controller for RAAF Rails controllers
      #
      # Provides common functionality for all RAAF controllers including
      # authentication, authorization, error handling, and response formatting.
      #
      # @abstract Subclass and override methods to implement specific controllers
      #
      # @example Creating a custom controller
      #   class MyAgentController < RAAF::Rails::Controllers::BaseController
      #     before_action :set_agent
      #
      #     def show
      #       respond_with_agent(@agent)
      #     end
      #
      #     private
      #
      #     def set_agent
      #       @agent = current_user.agents.find(params[:id])
      #     end
      #   end
      #
      # rubocop:disable Rails/ApplicationController
      # We inherit from ActionController::Base directly to avoid dependency on ApplicationController
      class BaseController < ::ActionController::Base
        # rubocop:enable Rails/ApplicationController
        include RAAF::Rails::Helpers::AgentHelper

        # Prevent CSRF attacks
        protect_from_forgery with: :exception

        # Handle common errors
        rescue_from ActiveRecord::RecordNotFound, with: :not_found
        rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
        rescue_from ActionController::ParameterMissing, with: :bad_request

        protected

        ##
        # Get current authenticated user
        #
        # Override this method to implement custom authentication logic.
        # By default, it uses the standard Rails current_user helper.
        #
        # @return [Object, nil] Current user or nil if not authenticated
        #
        def current_user
          # Override in application controller or use Devise/Doorkeeper helpers
          defined?(super) ? super : nil
        end

        ##
        # Ensure user is authenticated
        #
        # Redirects to login page if user is not authenticated.
        # Override to implement custom authentication logic.
        #
        # @return [void]
        #
        def authenticate_user!
          return if current_user

          respond_to do |format|
            format.html { redirect_to login_path, alert: I18n.t("raaf.rails.auth.please_sign_in") }
            format.json { render json: { error: "Unauthorized" }, status: :unauthorized }
          end
        end

        ##
        # Check if user is authorized for action
        #
        # @param resource [Object] Resource to check authorization for
        # @return [Boolean] True if authorized, false otherwise
        #
        def authorized?(resource)
          return false unless current_user

          # Basic ownership check - override for more complex logic
          resource.respond_to?(:user) && resource.user == current_user
        end

        ##
        # Render agent response in appropriate format
        #
        # @param agent [AgentModel] Agent to render
        # @param options [Hash] Additional options for rendering
        # @return [void]
        #
        def respond_with_agent(agent, options = {})
          respond_to do |format|
            format.html { render options.merge(locals: { agent: agent }) }
            format.json { render json: agent_to_json(agent) }
          end
        end

        ##
        # Render conversation response in appropriate format
        #
        # @param conversation [ConversationModel] Conversation to render
        # @param options [Hash] Additional options for rendering
        # @return [void]
        #
        def respond_with_conversation(conversation, options = {})
          respond_to do |format|
            format.html { render options.merge(locals: { conversation: conversation }) }
            format.json { render json: conversation_to_json(conversation) }
          end
        end

        private

        ##
        # Handle not found errors
        #
        # @param exception [ActiveRecord::RecordNotFound] Exception raised
        # @return [void]
        #
        def not_found(exception)
          respond_to do |format|
            format.html { render file: "public/404", status: :not_found, layout: false }
            format.json { render json: { error: exception.message }, status: :not_found }
          end
        end

        ##
        # Handle validation errors
        #
        # @param exception [ActiveRecord::RecordInvalid] Exception raised
        # @return [void]
        #
        def unprocessable_entity(exception)
          respond_to do |format|
            format.html do
              flash[:alert] = exception.record.errors.full_messages.join(", ")
              redirect_back(fallback_location: root_path)
            end
            format.json do
              render json: { errors: exception.record.errors }, status: :unprocessable_entity
            end
          end
        end

        ##
        # Handle bad request errors
        #
        # @param exception [ActionController::ParameterMissing] Exception raised
        # @return [void]
        #
        def bad_request(exception)
          respond_to do |format|
            format.html do
              flash[:alert] = "Bad request: #{exception.message}"
              redirect_back(fallback_location: root_path)
            end
            format.json do
              render json: { error: exception.message }, status: :bad_request
            end
          end
        end

        ##
        # Convert agent to JSON representation
        #
        # @param agent [AgentModel] Agent to convert
        # @return [Hash] JSON representation
        #
        def agent_to_json(agent)
          {
            id: agent.id,
            name: agent.name,
            instructions: agent.instructions,
            model: agent.model,
            tools: agent.tools,
            status: agent.status,
            created_at: agent.created_at,
            updated_at: agent.updated_at,
            metadata: agent.metadata
          }
        end

        ##
        # Convert conversation to JSON representation
        #
        # @param conversation [ConversationModel] Conversation to convert
        # @return [Hash] JSON representation
        #
        def conversation_to_json(conversation)
          {
            id: conversation.id,
            agent_id: conversation.agent_id,
            status: conversation.status,
            created_at: conversation.created_at,
            updated_at: conversation.updated_at,
            messages: conversation.messages.map { |m| message_to_json(m) },
            metadata: conversation.metadata
          }
        end

        ##
        # Convert message to JSON representation
        #
        # @param message [MessageModel] Message to convert
        # @return [Hash] JSON representation
        #
        def message_to_json(message)
          {
            id: message.id,
            role: message.role,
            content: message.content,
            created_at: message.created_at,
            usage: message.usage,
            metadata: message.metadata
          }
        end
      end
    end
  end
end
