# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module SpanDetail
        # GenericSpanComponent provides a fallback display for unknown or unsupported
        # span types, showing raw attributes and basic span information in a
        # clear, organized format.
        class GenericSpanComponent < RAAF::Rails::Tracing::SpanDetailBase
          def initialize(span:, **options)
            @span = span
            super(span: span, **options)
          end

          def view_template
            div(class: "space-y-6", data: { controller: "span-detail" }) do
              render_generic_overview
              render_span_overview
              render_timing_details
              render_raw_attributes if has_attributes?
              render_additional_data if has_additional_data?
            end
          end

          private

          def render_generic_overview
            div(class: "bg-gray-50 border border-gray-200 rounded-lg p-4") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-question-circle text-gray-600 text-xl")
                div(class: "flex-1") do
                  h3(class: "text-lg font-semibold text-gray-900") { "Unknown Span Type" }
                  p(class: "text-sm text-gray-600") do
                    "Kind: #{@span.kind || 'Unknown'} | This span type is not specifically supported yet."
                  end
                end
                render_generic_status_badge
              end
            end
          end

          def render_generic_status_badge
            color_classes = case @span.status&.downcase
                           when "success", "ok" then "bg-green-100 text-green-800 border-green-200"
                           when "error", "failed" then "bg-red-100 text-red-800 border-red-200"
                           when "warning" then "bg-yellow-100 text-yellow-800 border-yellow-200"
                           else "bg-gray-100 text-gray-800 border-gray-200"
                           end

            span(class: "px-3 py-1 text-sm font-medium rounded-full border #{color_classes}") do
              (@span.status || "Unknown").to_s.titleize
            end
          end

          def render_raw_attributes
            div(class: "bg-white border border-gray-200 rounded-lg shadow") do
              render_collapsible_header(
                "Raw Attributes (#{attribute_count} items)",
                "raw-attributes",
                "bi-code-square",
                expanded: should_expand_attributes?
              )
              div(id: "raw-attributes-content", class: expanded_class(should_expand_attributes?)) do
                div(class: "p-4 border-t border-gray-200") do
                  render_attributes_breakdown
                end
              end
            end
          end

          def render_attributes_breakdown
            div(class: "space-y-4") do
              # Group attributes by logical categories
              grouped_attributes.each do |category, attrs|
                next if attrs.empty?
                
                render_attribute_group(category, attrs)
              end
            end
          end

          def render_attribute_group(category, attributes)
            div(class: "border border-gray-200 rounded-lg overflow-hidden") do
              # Group header
              div(class: "bg-gray-50 px-4 py-2 border-b border-gray-200") do
                h5(class: "text-sm font-medium text-gray-800 flex items-center gap-2") do
                  render_category_icon(category)
                  category.to_s.humanize
                  span(class: "px-2 py-0.5 text-xs bg-gray-200 text-gray-600 rounded") { "#{attributes.length} items" }
                end
              end
              
              # Group content
              div(class: "p-3") do
                attributes.each do |key, value|
                  render_attribute_item(key, value)
                end
              end
            end
          end

          def render_category_icon(category)
            icon_class = case category
                        when :metadata then "bi-info-circle text-blue-600"
                        when :execution then "bi-play-circle text-green-600"
                        when :timing then "bi-clock text-yellow-600"
                        when :data then "bi-database text-purple-600"
                        when :error then "bi-exclamation-triangle text-red-600"
                        else "bi-tag text-gray-600"
                        end
            i(class: icon_class)
          end

          def render_attribute_item(key, value)
            div(class: "flex items-start justify-between py-2 border-b border-gray-100 last:border-b-0") do
              dt(class: "text-sm font-medium text-gray-700 w-1/3 break-words") { key.to_s }
              dd(class: "text-sm text-gray-900 w-2/3 break-words") do
                render_attribute_value(value)
              end
            end
          end

          def render_attribute_value(value)
            case value
            when String
              render_string_value(value)
            when Numeric
              span(class: "font-mono text-blue-800 bg-blue-50 px-1 py-0.5 rounded") { value.to_s }
            when TrueClass, FalseClass
              badge_class = value ? "bg-green-100 text-green-800" : "bg-red-100 text-red-800"
              span(class: "font-mono px-2 py-1 text-xs rounded #{badge_class}") { value.to_s }
            when Array
              render_array_value(value)
            when Hash
              render_hash_value(value)
            when NilClass
              span(class: "text-gray-400 italic font-mono") { "null" }
            else
              span(class: "text-gray-900 font-mono bg-gray-50 px-1 py-0.5 rounded") { value.to_s }
            end
          end

          def render_string_value(value)
            if value.length > 100
              value_id = "string-value-#{value.object_id}"
              div do
                div(id: "#{value_id}-preview") do
                  span(class: "text-gray-900") { truncate(value, length: 100) }
                end
                div(id: "#{value_id}-full", class: "hidden") do
                  span(class: "text-gray-900") { value }
                end
                button(
                  class: "text-xs text-blue-600 hover:text-blue-800 ml-2 px-2 py-1 hover:bg-blue-50 rounded transition-colors",
                  data: {
                    action: "click->span-detail#toggleValue",
                    target: value_id
                  }
                ) { "Show More" }
              end
            else
              span(class: "text-gray-900") { value }
            end
          end

          def render_array_value(value)
            if value.length <= 3
              div(class: "space-y-1") do
                value.each_with_index do |item, index|
                  div(class: "flex items-center gap-2 text-xs") do
                    span(class: "text-gray-400 font-mono") { "[#{index}]" }
                    span(class: "text-gray-700") { truncate(item.to_s, length: 50) }
                  end
                end
              end
            else
              array_id = "array-#{value.object_id}"
              div do
                button(
                  class: "text-sm text-blue-600 hover:text-blue-800 flex items-center gap-1 px-2 py-1 hover:bg-blue-50 rounded transition-colors",
                  data: {
                    action: "click->span-detail#toggleSection",
                    target: array_id
                  }
                ) do
                  i(class: "bi bi-chevron-right toggle-icon")
                  span(class: "button-text") { "Array (#{value.length} items)" }
                end
                div(id: array_id, class: "mt-2 space-y-1 hidden") do
                  value.each_with_index do |item, index|
                    div(class: "flex items-center gap-2 text-xs pl-4") do
                      span(class: "text-gray-400 font-mono") { "[#{index}]" }
                      span(class: "text-gray-700") { truncate(item.to_s, length: 60) }
                    end
                  end
                end
              end
            end
          end

          def render_hash_value(value)
            hash_id = "hash-#{value.object_id}"
            div do
              button(
                class: "text-sm text-blue-600 hover:text-blue-800 flex items-center gap-1 px-2 py-1 hover:bg-blue-50 rounded transition-colors",
                data: {
                  action: "click->span-detail#toggleSection",
                  target: hash_id
                }
              ) do
                i(class: "bi bi-chevron-right toggle-icon")
                span(class: "button-text") { "Object (#{value.keys.length} keys)" }
              end
              div(id: hash_id, class: "mt-2 hidden") do
                render_json_content(value, "hash-#{hash_id}-data")
              end
            end
          end

          def render_additional_data
            # Show any additional sections for generic spans
            additional_sections = [
              { key: :events, title: "Events", icon: "bi-calendar-event" },
              { key: :metrics, title: "Metrics", icon: "bi-graph-up" },
              { key: :logs, title: "Logs", icon: "bi-file-text" },
              { key: :custom, title: "Custom Data", icon: "bi-gear" }
            ]

            additional_sections.each do |section|
              data = @span.span_attributes&.dig(section[:key].to_s) || @span.span_attributes&.dig(section[:key])
              next unless data

              div(class: "bg-white border border-gray-200 rounded-lg shadow") do
                render_collapsible_header(section[:title], "additional-#{section[:key]}", section[:icon], expanded: false)
                div(id: "additional-#{section[:key]}-content", class: "p-4 border-t border-gray-200 hidden") do
                  render_json_content(data, "additional-#{section[:key]}-data")
                end
              end
            end
          end

          def render_collapsible_header(title, section_id, icon_class, expanded: true)
            button(
              class: "w-full flex items-center justify-between p-4 text-left hover:bg-gray-50 focus:outline-none focus:bg-gray-50",
              data: {
                action: "click->span-detail#toggleSection",
                target: "#{section_id}-content"
              }
            ) do
              div(class: "flex items-center gap-3") do
                i(class: "#{icon_class} text-gray-600 text-lg")
                h4(class: "text-md font-semibold text-gray-900") { title }
              end
              i(class: "bi #{expanded ? 'bi-chevron-down' : 'bi-chevron-right'} text-gray-400 toggle-icon")
            end
          end

          def render_json_content(data, element_id)
            div(class: "bg-gray-50 border border-gray-200 rounded") do
              div(class: "flex items-center justify-between p-2 bg-gray-100 border-b border-gray-200") do
                span(class: "text-xs font-medium text-gray-600") { "JSON Data" }
                button(
                  class: "text-xs text-blue-600 hover:text-blue-800 px-2 py-1 hover:bg-blue-50 rounded",
                  data: { action: "click->span-detail#copyJson", target: element_id }
                ) { "Copy" }
              end
              pre(id: element_id, class: "p-3 text-xs text-gray-700 overflow-x-auto whitespace-pre-wrap") do
                format_json_display(data)
              end
            end
          end

          # Helper methods
          def has_attributes?
            @span.span_attributes&.any?
          end

          def has_additional_data?
            return false unless @span.span_attributes
            
            %w[events metrics logs custom].any? do |key|
              @span.span_attributes.key?(key) || @span.span_attributes.key?(key.to_sym)
            end
          end

          def attribute_count
            @span.span_attributes&.keys&.count || 0
          end

          def should_expand_attributes?
            # Expand if there are few attributes or if it's a development environment
            attribute_count <= 5 || ::Rails.env.development?
          end

          def expanded_class(expanded)
            expanded ? "p-4 border-t border-gray-200" : "p-4 border-t border-gray-200 hidden"
          end

          def grouped_attributes
            return { other: [] } unless @span.span_attributes

            groups = {
              metadata: [],
              execution: [],
              timing: [],
              data: [],
              error: [],
              other: []
            }

            @span.span_attributes.each do |key, value|
              key_str = key.to_s.downcase
              category = case key_str
                        when /name|id|version|type|kind|status/
                          :metadata
                        when /execution|run|process|agent|model/
                          :execution
                        when /time|duration|start|end|created|updated/
                          :timing
                        when /input|output|data|result|response|content/
                          :data
                        when /error|exception|fail|stack|trace/
                          :error
                        else
                          :other
                        end
              
              groups[category] << [key, value]
            end

            # Remove empty groups
            groups.reject { |_, attrs| attrs.empty? }
          end

          def truncate(text, length: 100)
            return text unless text.is_a?(String) && text.length > length
            "#{text[0, length]}..."
          end
        end
      end
    end
  end
end