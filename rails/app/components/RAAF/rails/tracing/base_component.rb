# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class BaseComponent < Phlex::HTML
        include Phlex::Rails::Helpers::LinkTo
        include Phlex::Rails::Helpers::TimeAgoInWords
        include Phlex::Rails::Helpers::Pluralize
        include Phlex::Rails::Helpers::Truncate
        include Phlex::Rails::Helpers::FormWith
        include Phlex::Rails::Helpers::ContentFor
        include Phlex::Rails::Helpers::OptionsForSelect
        include Phlex::Rails::Helpers::Routes
        include Phlex::Rails::Helpers::CSRFMetaTags
        include Phlex::Rails::Helpers::CSPMetaTag
        include RAAF::Logging

        private

        # Route helper methods for the RAAF Rails engine
        def tracing_spans_path(params = {})
          path = "/raaf/tracing/spans"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def tracing_span_path(id)
          "/raaf/tracing/spans/#{id}"
        end

        def tracing_traces_path(params = {})
          path = "/raaf/tracing/traces"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def tracing_trace_path(id)
          "/raaf/tracing/traces/#{id}"
        end

        def tools_tracing_spans_path(params = {})
          path = "/raaf/tracing/spans/tools"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def flows_tracing_spans_path(params = {})
          path = "/raaf/tracing/spans/flows"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def dashboard_path
          "/raaf/dashboard"
        end

        def dashboard_performance_path
          "/raaf/dashboard/performance"
        end

        def dashboard_costs_path
          "/raaf/dashboard/costs"
        end

        def dashboard_errors_path
          "/raaf/dashboard/errors"
        end

        def tracing_timeline_path
          "/raaf/tracing/timeline"
        end

        def tracing_search_path
          "/raaf/tracing/search"
        end

        def render_status_badge(status, skip_reason: nil)
          render SkippedBadgeTooltip.new(status: status, skip_reason: skip_reason, style: :modern)
        end

        def render_kind_badge(kind)
          badge_class = case kind&.to_s&.downcase
                       when "agent" then "bg-blue-100 text-blue-800"
                       when "tool" then "bg-purple-100 text-purple-800"
                       when "response" then "bg-green-100 text-green-800"
                       when "span" then "bg-gray-100 text-gray-800"
                       else "bg-gray-100 text-gray-800"
                       end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge_class}") do
            kind&.to_s&.capitalize || "Unknown"
          end
        end

        def format_duration(ms)
          return "N/A" unless ms

          if ms < 1000
            "#{ms.round}ms"
          elsif ms < 60_000
            "#{(ms / 1000.0).round(1)}s"
          else
            minutes = (ms / 60_000).floor
            seconds = ((ms % 60_000) / 1000.0).round(1)
            "#{minutes}m #{seconds}s"
          end
        end

        def render_metric_card(title:, value:, color: "blue", icon: nil)
          # Define complete class strings to ensure Tailwind compilation
          border_class = case color
                        when "blue" then "border-blue-200"
                        when "green" then "border-green-200"
                        when "red" then "border-red-200"
                        when "yellow" then "border-yellow-200"
                        when "purple" then "border-purple-200"
                        else "border-blue-200"
                        end

          icon_bg_class = case color
                         when "blue" then "bg-blue-50"
                         when "green" then "bg-green-50"
                         when "red" then "bg-red-50"
                         when "yellow" then "bg-yellow-50"
                         when "purple" then "bg-purple-50"
                         else "bg-blue-50"
                         end

          icon_text_class = case color
                           when "blue" then "text-blue-600"
                           when "green" then "text-green-600"
                           when "red" then "text-red-600"
                           when "yellow" then "text-yellow-600"
                           when "purple" then "text-purple-600"
                           else "text-blue-600"
                           end

          div(class: "bg-white rounded-xl border #{border_class} shadow-sm hover:shadow-md transition-all duration-200 overflow-hidden") do
            div(class: "p-6") do
              div(class: "flex items-center justify-between") do
                div(class: "flex-1") do
                  div(class: "flex items-center gap-3 mb-3") do
                    if icon
                      div(class: "p-2 #{icon_bg_class} rounded-lg") do
                        i(class: "bi #{icon} #{icon_text_class} text-lg")
                      end
                    end
                    span(class: "text-xs font-semibold text-gray-500 uppercase tracking-wider") { title }
                  end
                  div(class: "text-2xl font-bold text-gray-900") { value.to_s }
                end
              end
            end
          end
        end

        def render_preline_button(text:, href: nil, variant: "primary", size: "sm", icon: nil, onclick: nil, **attrs)
          base_classes = "inline-flex items-center gap-x-2 text-#{size} font-semibold rounded-lg border transition-all"

          variant_classes = case variant
                           when "primary"
                             "border-blue-600 bg-blue-600 text-white hover:bg-blue-700 hover:border-blue-700"
                           when "secondary"
                             "border-gray-200 bg-white text-gray-800 shadow-sm hover:bg-gray-50"
                           when "danger"
                             "border-red-600 bg-red-600 text-white hover:bg-red-700 hover:border-red-700"
                           when "success"
                             "border-green-600 bg-green-600 text-white hover:bg-green-700 hover:border-green-700"
                           else
                             "border-gray-200 bg-white text-gray-800 shadow-sm hover:bg-gray-50"
                           end

          size_classes = case size
                        when "xs" then "px-2 py-1 text-xs"
                        when "sm" then "px-3 py-2 text-sm"
                        when "md" then "px-4 py-3 text-sm"
                        when "lg" then "px-4 py-3 text-base"
                        else "px-3 py-2 text-sm"
                        end

          classes = "#{base_classes} #{variant_classes} #{size_classes}"

          # Handle onclick by removing it and setting up proper event handling
          if onclick
            # Store the onclick code in a data attribute for later setup
            attrs[:data_onclick] = onclick
            # Remove onclick from attrs to avoid Phlex security error
            attrs.delete(:onclick)
          end

          if href
            a(href: href, class: classes, **attrs) do
              render_button_content(icon: icon, text: text)
            end
          else
            button(class: classes, **attrs) do
              render_button_content(icon: icon, text: text)
            end
          end
        end

        def render_button_content(icon:, text:)
          if icon
            i(class: "bi #{icon}")
          end
          plain text
        end

        def render_preline_table(&block)
          div(class: "flex flex-col") do
            div(class: "-m-1.5 overflow-x-auto") do
              div(class: "p-1.5 min-w-full inline-block align-middle") do
                div(class: "bg-white border border-gray-200 rounded-xl shadow-sm overflow-hidden") do
                  yield if block_given?
                end
              end
            end
          end
        end

        private
      end
    end
  end
end