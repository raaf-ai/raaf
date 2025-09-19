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

        private

        def render_status_badge(status)
          badge_class = case status&.to_s&.downcase
                       when "completed" then "bg-green-100 text-green-800"
                       when "failed" then "bg-red-100 text-red-800"
                       when "running" then "bg-yellow-100 text-yellow-800"
                       when "pending" then "bg-blue-100 text-blue-800"
                       else "bg-gray-100 text-gray-800"
                       end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge_class}") do
            status&.to_s&.capitalize || "Unknown"
          end
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
          div(class: "bg-white overflow-hidden shadow rounded-lg") do
            div(class: "p-5") do
              div(class: "flex items-center") do
                div(class: "flex-shrink-0") do
                  if icon
                    div(class: "w-8 h-8 bg-#{color}-500 rounded-md flex items-center justify-center") do
                      i(class: "bi #{icon} text-white")
                    end
                  end
                end
                div(class: "ml-5 w-0 flex-1") do
                  dt(class: "text-sm font-medium text-gray-500 truncate") { title }
                  dd do
                    div(class: "text-lg font-medium text-gray-900") { value }
                  end
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
      end
    end
  end
end