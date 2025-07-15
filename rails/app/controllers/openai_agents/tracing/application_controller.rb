# frozen_string_literal: true

require "raaf/logging"

module RubyAIAgentsFactory
  module Tracing
    # Base controller for the Ruby AI Agents Factory tracing engine
    #
    # Provides common functionality for all tracing controllers including:
    # - Authentication and authorization hooks
    # - Common error handling
    # - Shared before actions
    # - Helper methods for pagination and filtering
    class ApplicationController < ActionController::Base
      include RubyAIAgentsFactory::Logger
      protect_from_forgery with: :exception

      # Include helpers for content_tag
      include ActionView::Helpers::TagHelper

      # Layout for tracing interface
      layout "ruby_ai_agents_factory/tracing/application"

      # Common error handling
      rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
      rescue_from StandardError, with: :handle_error

      private

      # Handle record not found errors
      def record_not_found
        render "ruby_ai_agents_factory/tracing/shared/not_found", status: :not_found
      end

      # Handle general errors
      def handle_error(exception)
        log_error("Ruby AI Agents Factory Tracing Error",
          error: exception.message,
          error_class: exception.class.name,
          backtrace: exception.backtrace&.first(5)&.join("\n")
        )

        render "ruby_ai_agents_factory/tracing/shared/error",
               status: :internal_server_error,
               locals: { error: exception }
      end

      # Pagination helper
      def paginate_records(relation, page: 1, per_page: 25)
        page = [page.to_i, 1].max
        per_page = [per_page.to_i, 100].min
        per_page = 25 if per_page < 1

        relation.offset((page - 1) * per_page).limit(per_page)
      end

      # Time range helper for filtering
      def parse_time_range(params)
        start_time = params[:start_time].present? ? Time.parse(params[:start_time]) : 24.hours.ago
        end_time = params[:end_time].present? ? Time.parse(params[:end_time]) : Time.current

        start_time..end_time
      rescue ArgumentError
        24.hours.ago..Time.current
      end

      # Format duration for display
      def format_duration(milliseconds)
        return "N/A" unless milliseconds

        if milliseconds < 1000
          "#{milliseconds.round(1)}ms"
        elsif milliseconds < 60_000
          "#{(milliseconds / 1000).round(2)}s"
        else
          minutes = (milliseconds / 60_000).to_i
          seconds = ((milliseconds % 60_000) / 1000).round(1)
          "#{minutes}m #{seconds}s"
        end
      end
      helper_method :format_duration

      # Status badge helper
      def status_badge(status)
        return content_tag(:span, "N/A", class: "badge bg-secondary") if status.blank?

        case status.to_s.downcase
        when "ok", "completed"
          content_tag :span, status.capitalize, class: "badge bg-success"
        when "error", "failed"
          content_tag :span, status.capitalize, class: "badge bg-danger"
        when "running", "pending"
          content_tag :span, status.capitalize, class: "badge bg-warning text-dark"
        else
          content_tag :span, status.capitalize, class: "badge bg-secondary"
        end
      end
      helper_method :status_badge

      # Kind badge helper
      def kind_badge(kind)
        return content_tag(:span, "N/A", class: "badge bg-secondary") if kind.blank?

        color_map = {
          "agent" => "primary",
          "llm" => "info",
          "tool" => "success",
          "handoff" => "warning text-dark",
          "error" => "danger",
          "response" => "info",
          "guardrail" => "secondary",
          "mcp_list_tools" => "secondary",
          "speech_group" => "dark",
          "speech" => "dark",
          "transcription" => "dark",
          "custom" => "secondary",
          "internal" => "secondary",
          "trace" => "primary"
        }

        color_class = color_map[kind.to_s.downcase] || "secondary"
        content_tag :span, kind.to_s.capitalize, class: "badge bg-#{color_class}"
      end
      helper_method :kind_badge

      # Format token count with cost estimate
      def format_tokens(count, type = :input)
        return "-" unless count

        # Rough cost estimates per 1K tokens (adjust based on actual model)
        cost_per_1k = type == :input ? 0.01 : 0.03
        estimated_cost = (count / 1000.0 * cost_per_1k).round(4)

        "#{number_with_delimiter(count)} tokens (~$#{estimated_cost})"
      end
      helper_method :format_tokens
    end
  end
end
