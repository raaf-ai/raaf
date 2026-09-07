# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      # Module for organizing span detail components
      module SpanDetail
        # Main component class for rendering span details
        class Component < RAAF::Rails::Tracing::BaseComponent
          include RAAF::Rails::Tracing::PayloadTabs
          include RAAF::Rails::Tracing::SpanAccounting

          def initialize(span:, trace: nil, operation_details: nil, error_details: nil,
                         event_timeline: nil, params: {})
            @params_tab = params[:tab].to_s
            @span = span
            @trace = trace
            @operation_details = operation_details
            @error_details = error_details
            @event_timeline = event_timeline
          end

          # There is no span-detail screen in any canvas — the Tracing designs
          # stop at Trace detail. So this is built from the design's own
          # vocabulary rather than invented: the trace bar's identity strip, and
          # `SpanInspector`, which is exactly how the trace screen already shows
          # one span. What the page adds is what a trace's inspector has no room
          # for — every attribute, and the span's place in its trace.
          #
          # The per-kind deep dives below it are still their original markup.
          def view_template
            div(
              class: "raaf-page",
              data: {
                controller: "span-detail",
                span_detail_debug_value: ::Rails.env.development?
              }
            ) do
              replay_actions
              summary_bar
              div(class: "raaf-trace-split") do
                inspector
                side_column
              end
              kind_detail if dedicated_kind?
              render_children_section if @span.children.any?
              # events is nullable, and a page is not worth losing to a column
              # nobody filled: the processor writes [], but a span inserted by
              # hand or by an older writer has nil there.
              render_events_section if @span.events.present?
            end
          end

          # ── Replay ────────────────────────────────────────────────────────

          # The same controls the trace screen's inspector carries, since this
          # page and that one are the two places a single span is read.
          def replay_actions
            actions = span_replay_actions(@span)
            return if actions.empty?

            div(class: "raaf-page-actions") do
              actions.each { |action| render Atoms::Button.new(size: :sm, **action) }
            end
          end

          # ── Identity ──────────────────────────────────────────────────────

          def summary_bar
            div(class: "raaf-trace-bar") do
              render Atoms::Mono.new(@span.span_id)
              render Atoms::StatusBadge.new(@span.status)
              div(class: "raaf-trace-bar-stats") do
                summary_stats.each { |stat| summary_stat(stat) }
              end
            end
          end

          def summary_stat(stat)
            span(class: "raaf-trace-stat") do
              render Atoms::Icon.new(stat[:icon])
              plain stat[:label]
              render Atoms::Mono.new(stat[:value])
            end
          end

          # The bar carries the span's one accounting figure — its tokens, or
          # its charge — and a job span, which is billed neither way, carries
          # neither rather than a zero.
          def summary_stats
            [{ icon: "layers", label: "kind", value: @span.kind.to_s },
             { icon: "clock", label: "duration", value: format_duration(@span.duration_ms) },
             accounting_stat(@span),
             { icon: "diagram-3", label: "children", value: @span.children.count.to_s }].compact
          end

          # ── Inspector ─────────────────────────────────────────────────────

          def inspector
            render Organisms::SpanInspector.new(
              kind: @span.kind,
              name: @span.display_name,
              tab: tab,
              tabs: inspector_tabs,
              meta: inspector_meta,
              messages: payload_messages,
              error: inspector_error,
              tokens: token_rows,
              raw: raw_record
            )
          end

          def tab
            @tab ||= resolve_tab(@params_tab, tab_definitions, failed: failed?)
          end

          # One tab per payload section this span recorded, then the rest — of
          # which the accounting tab is offered only to a span that has
          # something to account for, and the error tab only to one that failed.
          def tab_definitions
            @tab_definitions ||= payload_tab_definitions(payload_messages,
                                                         accounting: accounting_label(@span),
                                                         error: failed?)
          end

          def inspector_tabs
            tab_definitions.map do |item|
              { id: item[:id], label: item[:label],
                href: "#{tracing_span_path(@span.span_id)}?tab=#{item[:id]}" }
            end
          end

          def inspector_meta
            attrs = @span.span_attributes || {}
            model = attrs["model"] || attrs.dig("llm", "model")

            [format_duration(@span.duration_ms),
             model.presence || "#{@span.kind} span",
             accounting_meta(@span),
             { value: @span.status, tone: @span.error? ? :bad : :ok }].compact
          end

          # The same payload shapes the trace screen reads, from the same
          # constant, so a span does not describe itself differently depending
          # on which page you opened it from.
          def payload_messages
            @payload_messages ||= payload_messages_from(@span.span_attributes)
          end

          # What makes the inspector open on the error rather than the payload.
          def failed?
            @span.error? || @span.status == "cancelled"
          end

          def inspector_error
            return nil unless failed?

            details = @error_details || @span.error_details || {}

            { klass: details[:exception_type].presence || "Error",
              message: details[:exception_message].presence ||
                details[:status_description].presence ||
                "The span reported #{@span.status}, but no exception was recorded on it.",
              backtrace: details[:exception_stacktrace] }
          end

          # This page used to read `usage` off the attributes itself, which is
          # one of the five shapes a span records its tokens in — so every span
          # that used any of the other four reported zero here, on the page
          # opened to find out what it had cost. {SpanAccounting} knows them all,
          # and knows which spans are not billed in tokens in the first place.
          def token_rows
            accounting_rows(@span,
                            extra: [{ label: "Duration",
                                      value: format_duration(@span.duration_ms), tone: :muted }])
          end

          def raw_record
            { span_id: @span.span_id, trace_id: @span.trace_id, parent_id: @span.parent_id,
              name: @span.name, kind: @span.kind, status: @span.status,
              start_time: @span.start_time, end_time: @span.end_time,
              duration_ms: @span.duration_ms, span_attributes: @span.span_attributes,
              events: @span.events }.to_json
          end

          # ── Side column ───────────────────────────────────────────────────

          def side_column
            div(class: "raaf-stack") do
              attributes_card
              relations_card
            end
          end

          # A trace's inspector has no room for these; on the span's own page
          # they are the reason to be here.
          def attributes_card
            render(Organisms::Card.new(title: "Attributes", flush: true)) do
              rows = (@span.span_attributes || {}).reject { |_, v| v.nil? || v.to_s.empty? }

              if rows.empty?
                render Molecules::EmptyState.new(icon: "braces", title: "No attributes",
                                                 text: "This span recorded none.")
              else
                rows.sort.each { |key, value| detail_line(key, stringify_value(value)) }
              end
            end
          end

          def relations_card
            render(Organisms::Card.new(title: "In its trace", flush: true)) do
              detail_line("Trace", @span.trace_id, href: tracing_trace_path(@span.trace_id))
              detail_line("Workflow", @trace&.workflow_name.presence || "—")
              detail_line("Parent", @span.parent_id.presence || "none",
                          href: @span.parent_id.presence && tracing_span_path(@span.parent_id))
              detail_line("Children", @span.children.count.to_s)
              detail_line("Started", @span.start_time&.strftime("%Y-%m-%d %H:%M:%S") || "—")
            end
          end

          def detail_line(label, value, href: nil)
            div(class: "raaf-config-row") do
              span(class: "raaf-config-label") { label.to_s }
              if href
                a(href: href, class: "raaf-mono raaf-config-value") { value.to_s }
              else
                render Atoms::Mono.new(value.to_s, class: "raaf-config-value")
              end
            end
          end

          # Kinds with a component of their own. The fallback for everything else
          # only repeats the id, name, kind, status and workflow the frame above
          # already shows — and it is still the original light-theme markup, so
          # on this page it reads as a white block of unreadable text. Skipped
          # rather than shown; nothing is lost, because it said nothing.
          DEDICATED_KINDS = %w[tool custom agent llm handoff guardrail pipeline response].freeze

          def dedicated_kind?
            DEDICATED_KINDS.include?(@span.kind.to_s.downcase)
          end

          def kind_detail
            render(Organisms::Card.new(title: "#{@span.kind.to_s.capitalize} detail")) do
              render_type_specific_component
            end
          end

          def stringify_value(value)
            value.is_a?(String) ? value : JSON.pretty_generate(value)
          rescue StandardError
            value.to_s
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
            when "component"
              render_component_span
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

          def render_component_span
            component_type = @span.span_attributes&.dig("component.type")
            case component_type
            when "search"
              render SearchSpanComponent.new(span: @span, trace: @trace)
            else
              render SpanDetail::GenericSpanComponent.new(span: @span, trace: @trace)
            end
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

                  render_detail_item("Workflow", @trace.workflow_name || "Unknown") if @trace

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
                  pre(id: "attributes-json",
                      class: "text-sm text-gray-700 whitespace-pre-wrap bg-gray-50 p-4 rounded border overflow-x-auto") do
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
                    dd(id: "tool-input-section-#{@span.span_id}", class: "mt-1 hidden",
                       data: { initially_collapsed: "true" }) do
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
                    dd(id: "tool-output-section-#{@span.span_id}", class: "mt-1 hidden",
                       data: { initially_collapsed: "true" }) do
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
                      span(class: "ml-2 px-2 py-1 text-xs bg-blue-100 text-blue-700 rounded") do
                        "#{value.keys.count} keys"
                      end
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
                  div(id: "attr-#{key.to_s.parameterize}-#{level}-content",
                      class: "space-y-2 max-h-64 overflow-y-auto hidden", data: { initially_collapsed: "true" }) do
                    render_nested_object(value)
                  end
                end
              when Array
                # Array value
                div do
                  h5(class: "text-sm font-semibold text-gray-800 flex items-center mb-2") do
                    i(class: "bi bi-list-ul text-green-600 mr-2")
                    key.to_s.humanize
                    span(class: "ml-2 px-2 py-1 text-xs bg-green-100 text-green-700 rounded") do
                      "#{value.length} items"
                    end
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
                      v.each_with_index do |item, _idx|
                        div { render_compact_value(item) }
                      end
                    else
                      div do
                        "#{v.first(2).map do |i|
                          render_compact_value(i)
                        end.join(', ')}... (+#{v.length - 2} more)"
                      end
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
              span(class: "font-mono px-1 py-0.5 rounded text-xs #{value ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}") do
                value.to_s
              end
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
                    span(class: "text-sm text-gray-900 font-mono bg-yellow-50 px-2 py-1 rounded") do
                      truncate(value, length: 100)
                    end
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
              span(class: "text-sm font-mono px-2 py-1 rounded #{value ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}") do
                value.to_s
              end
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
