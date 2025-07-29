# frozen_string_literal: true

module RAAF
  module Debug
    # Base controller for the Ruby AI Agents Factory debug interface
    #
    # Provides common functionality for all debug controllers including:
    # - Authentication and authorization hooks  
    # - Common error handling
    # - Shared before actions
    # - Helper methods for AI debugging
    class ApplicationController < ActionController::Base
      include RAAF::Logger

      protect_from_forgery with: :exception

      # Include helpers for content_tag
      include ActionView::Helpers::TagHelper

      # Layout for debug interface
      layout "openai_agents/debug/application"

      # Common error handling
      rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
      rescue_from StandardError, with: :handle_error

      private

      # Handle record not found errors
      def record_not_found
        render "openai_agents/debug/shared/not_found", status: :not_found
      end

      # Handle general errors
      def handle_error(exception)
        log_error("RAAF Debug Interface Error",
                  error: exception.message,
                  error_class: exception.class.name,
                  backtrace: exception.backtrace&.first(5)&.join("\n"))

        render "openai_agents/debug/shared/error",
               status: :internal_server_error,
               locals: { error: exception }
      end

      # Helper to format debug output
      def format_debug_output(output)
        return "" unless output

        case output
        when String
          output
        when Hash, Array
          JSON.pretty_generate(output)
        else
          output.inspect
        end
      end
      helper_method :format_debug_output

      # Helper to extract error details
      def extract_error_details(exception)
        {
          message: exception.message,
          class: exception.class.name,
          backtrace: exception.backtrace
        }
      end
    end
  end
end