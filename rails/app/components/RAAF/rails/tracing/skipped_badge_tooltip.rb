# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class SkippedBadgeTooltip < BaseComponent
        def initialize(status:, skip_reason: nil, style: :default)
          @status = status
          @skip_reason = skip_reason
          @style = style
        end

        def view_template
          if @skip_reason.present?
            render_tooltip_badge
          else
            render_standard_badge
          end
        end

        private

        def render_tooltip_badge
          div(class: "hs-tooltip inline-block skip-reason-tooltip") do
            span(
              class: "#{badge_classes} hs-tooltip-toggle cursor-help hover:ring-2 hover:ring-orange-200 hover:ring-opacity-50 transition-all duration-150",
              data: {
                hs_tooltip_delay_show: "100",
                hs_tooltip_delay_hide: "300"
              }
            ) do
              render_badge_content
            end

            # Tooltip content
            span(
              class: "hs-tooltip-content hs-tooltip-shown:opacity-100 hs-tooltip-shown:visible opacity-0 invisible transition-opacity duration-200 absolute z-50 py-2 px-3 bg-gray-900 text-xs font-medium text-white rounded-lg shadow-lg max-w-xs whitespace-normal break-words bottom-full left-1/2 transform -translate-x-1/2 mb-2 dark:bg-slate-800",
              role: "tooltip"
            ) do
              plain format_skip_reason(@skip_reason)
            end
          end
        end

        def render_standard_badge
          span(class: badge_classes) do
            render_badge_content
          end
        end

        def badge_classes
          case @style
          when :modern
            # Modern Tailwind style (for BaseComponent)
            case @status&.to_s&.downcase
            when "completed" then "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
            when "failed" then "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800"
            when "running" then "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800"
            when "pending" then "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800"
            when "skipped", "cancelled" then "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800"
            else "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
            end
          when :detailed
            # Detailed style with borders (for TraceDetail)
            base_classes = "rounded text-xs font-medium flex items-center gap-1"
            case @status&.to_s&.downcase
            when "ok", "completed" then "#{base_classes} px-2 py-1 bg-gray-100 text-gray-700 border border-gray-200"
            when "error", "failed" then "#{base_classes} px-2 py-1 bg-gray-200 text-gray-800 border border-gray-300"
            when "running" then "#{base_classes} px-2 py-1 bg-gray-100 text-gray-700 border border-gray-200"
            when "skipped", "cancelled" then "#{base_classes} px-2 py-1 bg-orange-100 text-orange-800 border border-orange-200"
            else "#{base_classes} px-2 py-1 bg-gray-100 text-gray-700 border border-gray-200"
            end
          else
            # Bootstrap style (for legacy components)
            case @status&.to_s&.downcase
            when "ok", "completed" then "badge bg-success"
            when "error", "failed" then "badge bg-danger"
            when "running", "pending" then "badge bg-warning text-dark"
            when "skipped", "cancelled" then "badge bg-warning text-dark"
            else "badge bg-secondary"
            end
          end
        end

        def render_badge_content
          case @style
          when :detailed
            # Detailed style with icon
            icon = case @status&.to_s&.downcase
                   when "ok", "completed" then "check-circle-fill"
                   when "error", "failed" then "x-circle-fill"
                   when "running" then "arrow-clockwise"
                   when "skipped", "cancelled" then "skip-forward"
                   else "clock"
                   end

            i(class: "bi bi-#{icon}")
            span { @status&.to_s&.capitalize || "Unknown" }
          else
            # Simple text content
            @status&.to_s&.capitalize || "Unknown"
          end
        end

        def format_skip_reason(reason)
          return reason if reason.blank?

          # Use Rails' built-in HTML entity decoding
          # This strips HTML tags and decodes entities safely
          decoded_reason = if defined?(ActionController::Base) && ActionController::Base.respond_to?(:helpers)
            # Use Rails sanitizer to strip tags and decode entities
            ActionController::Base.helpers.strip_tags(reason.to_s)
          else
            # Fallback for environments without Rails helpers
            CGI.unescapeHTML(reason.to_s)
          end

          return decoded_reason if decoded_reason.length <= 100

          # Truncate long reasons with ellipsis
          "#{decoded_reason[0..97]}..."
        end
      end
    end
  end
end