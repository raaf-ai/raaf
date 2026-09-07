# frozen_string_literal: true

require "raaf/logging"

module RAAF
  module Rails
    module Tracing
      # Base controller for the Ruby AI Agents Factory tracing engine
      #
      # Provides common functionality for all tracing controllers including:
      # - Authentication and authorization hooks
      # - Common error handling
      # - Shared before actions
      # - Helper methods for pagination and filtering
      class ApplicationController < ActionController::Base
        include RAAF::Logger
        include RAAF::Rails::TimeRange

        protect_from_forgery with: :exception

        # Disable layout since Phlex components are self-contained
        layout false

        # Include helpers for content_tag
        include ActionView::Helpers::TagHelper

        # Common error handling
        rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
        rescue_from StandardError, with: :handle_error

        private

        # Where a span is read.
        #
        # There is no span screen: a span opens its trace with itself
        # selected, so the waterfall says what ran before and after it. A span
        # whose trace was never recorded has no such place, and goes to the
        # list it can still be found in.
        #
        # @param span [SpanRecord]
        # @return [String]
        def span_location(span)
          return tracing_spans_path if span.trace_id.blank?

          tracing_trace_path(span.trace_id, span: span.span_id)
        end

        # Handle record not found errors
        def record_not_found
          not_found_component = RAAF::Rails::Tracing::NotFoundPage.new
          layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Not Found") do
            render not_found_component
          end

          render layout, status: :not_found
        end

        # Handle general errors
        def handle_error(exception)
          log_error("RAAF Tracing Error",
                    error: exception.message,
                    error_class: exception.class.name,
                    backtrace: exception.backtrace&.first(5)&.join("\n"))

          error_component = RAAF::Rails::Tracing::ErrorPage.new(error: exception)
          layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Error") do
            render error_component
          end

          render layout, status: :internal_server_error
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
end
