# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Base controller for RAAF Eval UI engine
      #
      # Provides common functionality for all UI controllers including:
      # - Configurable authentication
      # - Authorization callbacks
      # - Layout configuration
      # - Error handling
      #
      class ApplicationController < ActionController::Base
        # Use engine layout by default (can be overridden via config)
        layout -> { RAAF::Eval::UI.configuration.layout || "raaf/eval/ui/application" }

        # Apply authentication before all actions
        before_action :authenticate_user_from_config!

        # Helper methods available to all controllers and views
        helper_method :current_user

        # Handle common errors
        rescue_from StandardError, with: :handle_error

        private

        # Call configured authentication method
        def authenticate_user_from_config!
          method_name = RAAF::Eval::UI.configuration.authentication_method
          return unless method_name

          if respond_to?(method_name, true)
            send(method_name)
          elsif defined?(Rails) && Rails.application.respond_to?(method_name)
            Rails.application.send(method_name)
          end
        end

        # Get current user via configured method
        def current_user
          method_name = RAAF::Eval::UI.configuration.current_user_method
          return nil unless method_name

          if respond_to?(method_name, true)
            send(method_name)
          elsif defined?(Rails) && Rails.application.respond_to?(method_name)
            Rails.application.send(method_name)
          end
        end

        # Authorize span access using configured callback
        def authorize_span_access!(span)
          callback = RAAF::Eval::UI.configuration.authorize_span_access
          return true unless callback

          unless callback.call(current_user, span)
            flash[:alert] = "You don't have permission to access this span"
            redirect_to root_path
          end
        end

        # Handle errors gracefully
        def handle_error(exception)
          Rails.logger.error("RAAF Eval UI Error: #{exception.class} - #{exception.message}")
          Rails.logger.error(exception.backtrace.join("\n"))

          respond_to do |format|
            format.html do
              flash[:error] = "An error occurred: #{exception.message}"
              redirect_back(fallback_location: root_path)
            end
            format.json do
              render json: { error: exception.message }, status: :internal_server_error
            end
            format.turbo_stream do
              render turbo_stream: turbo_stream.replace(
                "error_container",
                partial: "raaf/eval/ui/shared/error",
                locals: { error: exception.message }
              )
            end
          end
        end
      end
    end
  end
end
