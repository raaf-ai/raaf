# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      # Module for organizing span detail components
      module SpanDetail
        # Main component class for rendering span details
        class Component < RAAF::Rails::Tracing::BaseComponent
        def initialize(span:, trace: nil, operation_details: nil, error_details: nil, event_timeline: nil)
          @span = span
          @trace = trace
          @operation_details = operation_details
          @error_details = error_details
          @event_timeline = event_timeline
        end

        def view_template
          div(
            class: "p-6",
            data: {
              controller: "span-detail",
              span_detail_debug_value: ::Rails.env.development?
            }
          ) do
            render_header
            render_type_specific_component
            render_children_section if @span.children.any?
            render_events_section if @span.events.any?
            render_error_section if @error_details
          end
        end

        private

        # Component routing logic - routes to type-specific components based on span.kind
        def render_type_specific_component
          case @span.kind&.downcase
          when "tool", "custom"
            render_tool_span_component
          when "agent"
            render_agent_span_component
          when "llm"
            render_llm_span_component
          when "handoff"
            render_handoff_span_component
          when "guardrail"
            render_guardrail_span_component
          when "pipeline"
            render_pipeline_span_component
          when "response"
            render_response_span_component
          when "speech_group", "speech", "transcription", "mcp_list_tools"
            render_specialized_span_component
          else
            render_generic_span_component
          end
        end

        # Render dedicated component classes for each span type
        def render_tool_span_component
          render ToolSpanComponent.new(span: @span, trace: @trace)
        end

        def render_agent_span_component
          render AgentSpanComponent.new(span: @span, trace: @trace)
        end

        def render_llm_span_component
          render LlmSpanComponent.new(span: @span, trace: @trace)
        end

        def render_handoff_span_component
          render HandoffSpanComponent.new(span: @span, trace: @trace)
        end

        def render_guardrail_span_component
          render SpanDetail::GuardrailSpanComponent.new(span: @span, trace: @trace)
        end

        def render_pipeline_span_component
          render SpanDetail::PipelineSpanComponent.new(span: @span, trace: @trace)
        end

        def render_response_span_component
          base_component = SpanDetailBase.new(span: @span, trace: @trace)
          render base_component.render_span_overview
          render base_component.render_timing_details
          render_attributes_section
          # Response-specific sections will be added in later tasks
        end

        def render_specialized_span_component
          base_component = SpanDetailBase.new(span: @span, trace: @trace)
          render base_component.render_span_overview
          render base_component.render_timing_details
          render_attributes_section
          # Specialized span sections will be added in later tasks
        end

        def render_generic_span_component
          render SpanDetail::GenericSpanComponent.new(span: @span, trace: @trace)
        end

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") do
                "Span Detail"
              end
              p(class: "mt-1 text-sm text-gray-500") do
                plain "#{@span.name} • "
                render_kind_badge(@span.kind)
                plain " • "
                render_status_badge(@span.status)
              end
            end

            div(class: "mt-4 flex space-x-3 sm:mt-0 sm:ml-4") do
              if @trace
                render_preline_button(
                  text: "View Trace",
                  href: tracing_trace_path(@span.trace_id),
                  variant: "primary",
                  icon: "bi-diagram-3"
                )
              end

              render_preline_button(
                text: "Back to Spans",
                href: tracing_spans_path,
                variant: "secondary",
                icon: "bi-arrow-left"
              )
            end
          end
        end

        def render_overview_section
          div(class: "bg-white overflow-hidden shadow rounded-lg mb-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg leading-6 font-medium text-gray-900") { "Overview" }
            end

            div(class: "px-4 py-5 sm:p-6") do
              dl(class: "grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2") do
                render_detail_item("Span ID", @span.span_id, monospace: true)
                render_detail_item("Trace ID", @span.trace_id, monospace: true)
                render_detail_item("Parent ID", @span.parent_id || "None", monospace: true)
                render_detail_item("Name", @span.name)
                render_detail_item("Kind", render_kind_badge(@span.kind))
                render_detail_item("Status", render_status_badge(@span.status))

                if @trace
                  render_detail_item("Workflow", @trace.workflow_name || "Unknown")
                end

                render_detail_item("Depth", @span.depth || 0)
              end
            end
          end
        end

        def render_timing_section
          div(class: "bg-white overflow-hidden shadow rounded-lg mb-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg leading-6 font-medium text-gray-900") { "Timing Information" }
            end

            div(class: "px-4 py-5 sm:p-6") do
              dl(class: "grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2") do
                render_detail_item("Start Time", @span.start_time&.strftime("%Y-%m-%d %H:%M:%S.%3N UTC"))
                render_detail_item("End Time", @span.end_time&.strftime("%Y-%m-%d %H:%M:%S.%3N UTC"))
                render_detail_item("Duration", format_duration(@span.duration_ms))

                if @span.start_time
                  render_detail_item("Time Since Start", time_ago_in_words(@span.start_time) + " ago")
                end
              end
            end
          end
        end

        def render_attributes_section
          return unless @span.span_attributes&.any?

          div(class: "bg-white overflow-hidden shadow rounded-lg mb-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              div(class: "flex items-center justify-between") do
                h3(class: "text-lg leading-6 font-medium text-gray-900") { "Attributes" }
                div(class: "flex items-center space-x-2") do
                  span(class: "text-xs text-gray-500") { "#{@span.span_attributes.keys.count} attributes" }
                  button(
                    class: "text-blue-600 hover:text-blue-800 text-sm",
                    data: {
                      action: "click->span-detail#toggleAttributesView",
                      expanded_text: "Show Structured",
                      collapsed_text: "Show Raw JSON"
                    }
                  ) do
                    span(class: "button-text") { "Toggle View" }
                  end
                end
              end
            end

            div(id: "attributes-content", class: "px-4 py-5 sm:p-6") do
              # Show structured view by default
              div(id: "attributes-structured", class: "space-y-4") do
                render_structured_attributes(@span.span_attributes)
              end

              # Raw JSON view (hidden by default)
              div(id: "attributes-raw", class: "hidden") do
                div(class: "mb-3 flex items-center justify-between") do
                  h4(class: "text-sm font-medium text-gray-700") { "Raw JSON" }
                  button(
                    class: "text-xs text-blue-600 hover:text-blue-800",
                    data: {
                      action: "click->span-detail#copyJson",
                      target: "attributes-json"
                    }
                  ) { "Copy JSON" }
                end
                pre(id: "attributes-json", class: "text-sm text-gray-700 whitespace-pre-wrap bg-gray-50 p-4 rounded border overflow-x-auto") do
                  JSON.pretty_generate(@span.span_attributes)
                end
              end
            end
          end
        end

        def render_tool_details_section
          return unless tool_or_custom_span?

          tool_data = extract_tool_data_from_span(@span)

          div(class: "bg-white overflow-hidden shadow rounded-lg mb-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg leading-6 font-medium text-gray-900") do
                @span.kind == "tool" ? "Tool Call Details" : "Custom Function Details"
              end
            end

            div(class: "px-4 py-5 sm:p-6 space-y-6") do
              if tool_data[:function_name]
                div do
                  dt(class: "text-sm font-medium text-gray-500") { "Function Name" }
                  dd(class: "mt-1 text-sm text-gray-900 font-mono") { tool_data[:function_name] }
                end
              end

              # Input Parameters
              if tool_data[:input]
                div do
                  div(class: "flex items-center justify-between mb-2") do
                    dt(class: "text-sm font-medium text-gray-500") { "Input Parameters" }
                    button(
                      class: "text-blue-600 hover:text-blue-800 text-xs flex items-center gap-1",
                      data: {
                        action: "click->span-detail#toggleToolInput",
                        target: "tool-input-section-#{@span.span_id}",
                        expanded_text: "Collapse",
                        collapsed_text: "Expand"
                      }
                    ) do
                      i(class: "bi bi-chevron-right toggle-icon")
                      span(class: "button-text") { "Toggle Details" }
                    end
                  end
                  dd(id: "tool-input-section-#{@span.span_id}", class: "mt-1 hidden", data: { initially_collapsed: "true" }) do
                    div(class: "border border-blue-200 rounded-md") do
                      div(class: "bg-blue-50 px-3 py-2 border-b border-blue-200") do
                        strong(class: "text-blue-900") { "Input Data" }
                      end
                      div(class: "p-3 bg-white") do
                        pre(class: "text-xs text-gray-700 whitespace-pre-wrap bg-gray-50 p-3 rounded border overflow-x-auto") do
                          format_json_display(tool_data[:input])
                        end
                      end
                    end
                  end
                end
              end

              # Output Results
              if tool_data[:output]
                div do
                  div(class: "flex items-center justify-between mb-2") do
                    dt(class: "text-sm font-medium text-gray-500") { "Output Results" }
                    button(
                      class: "text-green-600 hover:text-green-800 text-xs flex items-center gap-1",
                      data: {
                        action: "click->span-detail#toggleToolOutput",
                        target: "tool-output-section-#{@span.span_id}",
                        expanded_text: "Collapse",
                        collapsed_text: "Expand"
                      }
                    ) do
                      i(class: "bi bi-chevron-right toggle-icon")
                      span(class: "button-text") { "Toggle Details" }
                    end
                  end
                  dd(id: "tool-output-section-#{@span.span_id}", class: "mt-1 hidden", data: { initially_collapsed: "true" }) do
                    div(class: "border border-green-200 rounded-md") do
                      div(class: "bg-green-50 px-3 py-2 border-b border-green-200") do
                        strong(class: "text-green-900") { "Output Data" }
                      end
                      div(class: "p-3 bg-white") do
                        pre(class: "text-xs text-gray-700 whitespace-pre-wrap bg-gray-50 p-3 rounded border overflow-x-auto") do
                          format_json_display(tool_data[:output])
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end

        def render_children_section
          div(class: "bg-white overflow-hidden shadow rounded-lg mb-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg leading-6 font-medium text-gray-900") do
                "Child Spans (#{@span.children.count})"
              end
            end

            div(class: "overflow-x-auto") do
              table(class: "min-w-full divide-y divide-gray-200") do
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Name" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Kind" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Status" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Duration" }
                  end
                end

                tbody(class: "bg-white divide-y divide-gray-200") do
                  @span.children.each do |child|
                    tr(class: "hover:bg-gray-50") do
                      td(class: "px-4 py-3 text-sm") do
                        link_to(
                          child.name,
                          tracing_span_path(child.span_id),
                          class: "text-blue-600 hover:text-blue-900"
                        )
                      end
                      td(class: "px-4 py-3 text-sm") { render_kind_badge(child.kind) }
                      td(class: "px-4 py-3 text-sm") { render_status_badge(child.status) }
                      td(class: "px-4 py-3 text-sm text-gray-900") { format_duration(child.duration_ms) }
                    end
                  end
                end
              end
            end
          end
        end

        def render_events_section
          div(class: "bg-white overflow-hidden shadow rounded-lg mb-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              div(class: "flex items-center justify-between") do
                h3(class: "text-lg leading-6 font-medium text-gray-900") do
                  "Events (#{@span.events.count})"
                end
                button(
                  class: "text-blue-600 hover:text-blue-800 text-sm flex items-center gap-1",
                  data: {
                    action: "click->span-detail#toggleSection",
                    target: "events-content",
                    expanded_text: "Collapse",
                    collapsed_text: "Expand"
                  }
                ) do
                  i(class: "bi bi-chevron-right toggle-icon")
                  span(class: "button-text") { "Toggle Details" }
                end
              end
            end

            div(id: "events-content", class: "px-4 py-5 sm:p-6 hidden", data: { initially_collapsed: "true" }) do
              pre(class: "text-sm text-gray-700 whitespace-pre-wrap bg-gray-50 p-4 rounded border overflow-x-auto") do
                JSON.pretty_generate(@span.events)
              end
            end
          end
        end

        def render_error_section
          div(class: "bg-red-50 border border-red-200 rounded-lg p-6 mb-6") do
            div(class: "flex items-center mb-4") do
              i(class: "bi bi-exclamation-triangle text-red-600 text-xl mr-3")
              h3(class: "text-lg font-medium text-red-900") { "Error Details" }
            end

            div(class: "space-y-4") do
              if @error_details.is_a?(Hash)
                @error_details.each do |key, value|
                  div do
                    dt(class: "text-sm font-medium text-red-700") { key.to_s.humanize }
                    dd(class: "mt-1 text-sm text-red-900") do
                      if value.is_a?(String) && value.length > 200
                        div do
                          div(id: "error-#{key}-preview") { truncate(value, length: 200) }
                          div(id: "error-#{key}-full", class: "hidden") { value }
                          button(
                            class: "text-red-600 hover:text-red-800 text-xs mt-1",
                            data: {
                              action: "click->span-detail#toggleErrorDetail",
                              target: "error-#{key}"
                            }
                          ) { "Show More" }
                        end
                      else
                        value.to_s
                      end
                    end
                  end
                end
              else
                pre(class: "text-sm text-red-900 whitespace-pre-wrap bg-red-100 p-3 rounded border") do
                  @error_details.to_s
                end
              end
            end
          end
        end

        def render_detail_item(label, value, monospace: false)
          div do
            dt(class: "text-sm font-medium text-gray-500") { label }
            dd(class: "mt-1 text-sm text-gray-900 #{'font-mono' if monospace}") { value }
          end
        end

        def render_structured_attributes(attributes, level = 0)
          return unless attributes

          # Group attributes logically for better organization
          grouped_attrs = group_attributes(attributes)

          grouped_attrs.each do |group_name, group_attrs|
            div(class: "mb-6") do
              # Group header
              if group_name != :other
                div(class: "mb-3 pb-2 border-b border-gray-200") do
                  h4(class: "text-md font-semibold text-gray-900") { group_name.to_s.humanize }
                end
              end

              # Group content
              div(class: "space-y-3") do
                group_attrs.each do |key, value|
                  render_single_attribute(key, value, level)
                end
              end
            end
          end
        end

        def group_attributes(attributes)
          grouped = {
            pipeline: {},
            context: {},
            execution: {},
            results: {},
            other: {}
          }

          attributes.each do |key, value|
            key_str = key.to_s
            case key_str
            when /^pipeline\./
              grouped[:pipeline][key] = value
            when /context|initial_context|market_data|icp_constraints/
              grouped[:context][key] = value
            when /execution|duration|agents|success|result_keys/
              grouped[:execution][key] = value
            when /result|final_result|transformation/
              grouped[:results][key] = value
            else
              grouped[:other][key] = value
            end
          end

          # Remove empty groups
          grouped.reject { |_, attrs| attrs.empty? }
        end

        def render_single_attribute(key, value, level = 0)
          div(class: "bg-gray-50 rounded-lg p-3") do
            case value
            when Hash
              # Nested object
              div do
                div(class: "flex items-center justify-between mb-3") do
                  h5(class: "text-sm font-semibold text-gray-800 flex items-center") do
                    i(class: "bi bi-braces text-blue-600 mr-2")
                    key.to_s.humanize
                    span(class: "ml-2 px-2 py-1 text-xs bg-blue-100 text-blue-700 rounded") { "#{value.keys.count} keys" }
                  end
                  button(
                    class: "text-xs px-2 py-1 bg-white border rounded hover:bg-gray-50 flex items-center gap-1",
                    data: {
                      action: "click->span-detail#toggleAttributeGroup",
                      target: "attr-#{key.to_s.parameterize}-#{level}-content",
                      expanded_text: "Collapse",
                      collapsed_text: "Expand"
                    }
                  ) do
                    i(class: "bi bi-chevron-right toggle-icon")
                    span(class: "button-text") { "Toggle" }
                  end
                end
                div(id: "attr-#{key.to_s.parameterize}-#{level}-content", class: "space-y-2 max-h-64 overflow-y-auto hidden", data: { initially_collapsed: "true" }) do
                  render_nested_object(value)
                end
              end
            when Array
              # Array value
              div do
                h5(class: "text-sm font-semibold text-gray-800 flex items-center mb-2") do
                  i(class: "bi bi-list-ul text-green-600 mr-2")
                  key.to_s.humanize
                  span(class: "ml-2 px-2 py-1 text-xs bg-green-100 text-green-700 rounded") { "#{value.length} items" }
                end
                div(class: "space-y-1 max-h-48 overflow-y-auto") do
                  render_array_items(value)
                end
              end
            else
              # Simple key-value pair
              div(class: "flex items-start justify-between") do
                dt(class: "text-sm font-medium text-gray-700 flex items-center min-w-0 flex-1") do
                  render_attribute_icon(value)
                  key.to_s.humanize
                end
                dd(class: "ml-4 text-right") do
                  render_attribute_value(value)
                end
              end
            end
          end
        end

        def render_nested_object(obj)
          obj.each do |k, v|
            div(class: "flex items-start py-1 border-b border-gray-200 last:border-b-0") do
              dt(class: "text-xs font-medium text-gray-600 w-1/3") { k.to_s.humanize }
              dd(class: "text-xs text-gray-800 w-2/3 break-words") do
                case v
                when Array
                  if v.length <= 3
                    v.each_with_index do |item, idx|
                      div { render_compact_value(item) }
                    end
                  else
                    div { "#{v.first(2).map { |i| render_compact_value(i) }.join(', ')}... (+#{v.length - 2} more)" }
                  end
                when Hash
                  span(class: "text-gray-500 italic") { "Object with #{v.keys.count} keys" }
                else
                  render_compact_value(v)
                end
              end
            end
          end
        end

        def render_array_items(array)
          if array.length <= 5
            array.each_with_index do |item, index|
              div(class: "flex items-start py-1") do
                span(class: "text-xs text-gray-400 mr-2 mt-1 w-8") { "#{index + 1}." }
                div(class: "flex-1 text-sm") { render_compact_value(item) }
              end
            end
          else
            array.first(3).each_with_index do |item, index|
              div(class: "flex items-start py-1") do
                span(class: "text-xs text-gray-400 mr-2 mt-1 w-8") { "#{index + 1}." }
                div(class: "flex-1 text-sm") { render_compact_value(item) }
              end
            end
            div(class: "text-xs text-gray-500 italic py-1") { "... and #{array.length - 3} more items" }
          end
        end

        def render_compact_value(value)
          case value
          when String
            if value.length > 100
              truncated = truncate(value, length: 100)
              span(class: "text-gray-900") { truncated }
            else
              span(class: "text-gray-900") { value }
            end
          when Numeric
            span(class: "font-mono text-blue-800") { value.to_s }
          when TrueClass, FalseClass
            span(class: "font-mono px-1 py-0.5 rounded text-xs #{value ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}") { value.to_s }
          when Hash
            span(class: "text-gray-500 italic") { "Object (#{value.keys.count} keys)" }
          when Array
            span(class: "text-gray-500 italic") { "Array (#{value.length} items)" }
          when NilClass
            span(class: "text-gray-400 italic") { "null" }
          else
            span(class: "text-gray-900") { value.to_s }
          end
        end

        def render_attribute_icon(value)
          icon_class = case value
                      when String then "bi-quote text-yellow-600"
                      when Numeric then "bi-hash text-blue-600"
                      when TrueClass, FalseClass then "bi-toggle-on text-green-600"
                      when NilClass then "bi-x-circle text-gray-400"
                      else "bi-circle text-gray-600"
                      end
          i(class: "#{icon_class} mr-2 text-xs")
        end

        def render_attribute_value(value)
          case value
          when String
            if value.length > 100
              div do
                div(id: "value-#{value.object_id}-preview") do
                  span(class: "text-sm text-gray-900 font-mono bg-yellow-50 px-2 py-1 rounded") { truncate(value, length: 100) }
                end
                div(id: "value-#{value.object_id}-full", class: "hidden") do
                  span(class: "text-sm text-gray-900 font-mono bg-yellow-50 px-2 py-1 rounded") { value }
                end
                button(
                  class: "text-xs text-blue-600 hover:text-blue-800 ml-2",
                  data: {
                    action: "click->span-detail#toggleValue",
                    target: "value-#{value.object_id}"
                  }
                ) { "Show More" }
              end
            else
              span(class: "text-sm text-gray-900 font-mono bg-yellow-50 px-2 py-1 rounded") { value }
            end
          when Numeric
            span(class: "text-sm text-gray-900 font-mono bg-blue-50 px-2 py-1 rounded text-blue-800") { value.to_s }
          when TrueClass, FalseClass
            span(class: "text-sm font-mono px-2 py-1 rounded #{value ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}") { value.to_s }
          when NilClass
            span(class: "text-sm text-gray-400 font-mono bg-gray-100 px-2 py-1 rounded") { "null" }
          else
            span(class: "text-sm text-gray-900 font-mono bg-gray-50 px-2 py-1 rounded") { value.to_s }
          end
        end

        def tool_or_custom_span?
          %w[tool custom].include?(@span.kind)
        end

        def extract_tool_data_from_span(span)
          if span.kind == "tool"
            function_data = span.span_attributes&.dig("function") || {}
            {
              function_name: function_data["name"],
              input: function_data["input"],
              output: function_data["output"]
            }
          else # custom
            {
              function_name: span.span_attributes&.dig("custom", "name") || span.name,
              input: span.span_attributes&.dig("custom", "data") || {},
              output: span.span_attributes&.dig("output") || span.span_attributes&.dig("result")
            }
          end
        end

        def format_json_display(data)
          return "N/A" if data.nil?

          case data
          when String
            begin
              JSON.pretty_generate(JSON.parse(data))
            rescue JSON::ParserError
              data
            end
          when Hash, Array
            JSON.pretty_generate(data)
          else
            data.to_s
          end
        end

        # Removed inline JavaScript - now using Stimulus controller
        # All interactive functionality is handled by span_detail_controller.js
        end
      end
    end
  end
end