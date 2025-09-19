# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class TraceDetail < Phlex::HTML
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::TimeAgoInWords
      include Phlex::Rails::Helpers::Pluralize
      include Phlex::Rails::Helpers::Routes
      include Components::Preline
      include Components

      def initialize(trace:)
        @trace = trace
      end

      def view_template
        div(class: "min-h-screen bg-gradient-to-br from-slate-50 to-blue-50") do
          Container(class: "max-w-7xl mx-auto py-8 px-6 space-y-8") do
            render_header
            render_trace_overview
            render_performance_insights
            render_spans_hierarchy
          end
        end
      end

      private

      def render_header
        div(class: "relative overflow-hidden bg-white rounded-2xl shadow-sm border border-gray-100") do
          # Background gradient
          div(class: "absolute inset-0 bg-gradient-to-r from-blue-500/5 to-purple-500/5")

          div(class: "relative p-8") do
            Flex(justify: :between, align: :start) do
              div(class: "flex-1") do
                div(class: "flex items-center gap-3 mb-3") do
                  div(class: "p-3 bg-blue-500 rounded-xl shadow-lg") do
                    i(class: "bi bi-diagram-3 text-white text-xl")
                  end
                  div do
                    h1(class: "text-3xl font-bold text-gray-900 mb-1") { @trace.workflow_name }
                    render_status_badge(@trace.status)
                  end
                end

                div(class: "flex items-center gap-6 text-sm text-gray-600") do
                  div(class: "flex items-center gap-2") do
                    i(class: "bi bi-fingerprint text-gray-400")
                    span(class: "font-mono") { @trace.trace_id }
                  end
                  div(class: "flex items-center gap-2") do
                    i(class: "bi bi-clock text-gray-400")
                    span { "#{time_ago_in_words(@trace.started_at)} ago" }
                  end
                  div(class: "flex items-center gap-2") do
                    i(class: "bi bi-calendar text-gray-400")
                    span { @trace.started_at.strftime("%B %d, %Y at %I:%M %p") }
                  end
                end
              end

              div(class: "flex gap-3") do
                div(
                  class: "px-4 py-2 bg-blue-50 hover:bg-blue-100 text-blue-700 rounded-lg border border-blue-200 transition-colors duration-200 flex items-center gap-2 cursor-pointer select-all",
                  title: "Click to select trace ID"
                ) do
                  i(class: "bi bi-fingerprint text-sm")
                  span(class: "font-mono text-sm") { @trace.trace_id }
                end

                link_to(
                  "/raaf/tracing/traces",
                  class: "px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-lg transition-colors duration-200 flex items-center gap-2"
                ) do
                  i(class: "bi bi-arrow-left text-sm")
                  span { "Back to Traces" }
                end
              end
            end
          end
        end
      end

      def render_trace_overview
        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6") do
          # Duration Card
          div(class: "bg-white rounded-xl p-6 shadow-sm border border-gray-100 hover:shadow-md transition-all duration-200") do
            div(class: "flex items-center justify-between mb-3") do
              div(class: "p-2 bg-green-100 rounded-lg") do
                i(class: "bi bi-stopwatch text-green-600 text-lg")
              end
              span(class: "text-xs text-gray-500 font-medium") { "DURATION" }
            end
            div(class: "text-2xl font-bold text-gray-900 mb-1") { format_duration(@trace.duration_ms) }
            div(class: "text-sm text-gray-500") { "Total execution time" }
          end

          # Spans Card
          div(class: "bg-white rounded-xl p-6 shadow-sm border border-gray-100 hover:shadow-md transition-all duration-200") do
            div(class: "flex items-center justify-between mb-3") do
              div(class: "p-2 bg-blue-100 rounded-lg") do
                i(class: "bi bi-collection text-blue-600 text-lg")
              end
              span(class: "text-xs text-gray-500 font-medium") { "SPANS" }
            end
            div(class: "text-2xl font-bold text-gray-900 mb-1") { @trace.spans.count.to_s }
            div(class: "text-sm text-gray-500") do
              "#{@trace.spans.errors.count} errors" if @trace.spans.errors.any?
              "All successful" if @trace.spans.errors.empty?
            end
          end

          # Performance Card
          div(class: "bg-white rounded-xl p-6 shadow-sm border border-gray-100 hover:shadow-md transition-all duration-200") do
            div(class: "flex items-center justify-between mb-3") do
              div(class: "p-2 bg-purple-100 rounded-lg") do
                i(class: "bi bi-speedometer2 text-purple-600 text-lg")
              end
              span(class: "text-xs text-gray-500 font-medium") { "PERFORMANCE" }
            end
            div(class: "text-2xl font-bold text-gray-900 mb-1") do
              if @trace.duration_ms && @trace.duration_ms < 1000
                "Fast"
              elsif @trace.duration_ms && @trace.duration_ms < 5000
                "Good"
              else
                "Slow"
              end
            end
            div(class: "text-sm text-gray-500") { "Execution speed" }
          end

          # Success Rate Card
          div(class: "bg-white rounded-xl p-6 shadow-sm border border-gray-100 hover:shadow-md transition-all duration-200") do
            div(class: "flex items-center justify-between mb-3") do
              div(class: "p-2 bg-orange-100 rounded-lg") do
                i(class: "bi bi-graph-up text-orange-600 text-lg")
              end
              span(class: "text-xs text-gray-500 font-medium") { "SUCCESS RATE" }
            end
            div(class: "text-2xl font-bold text-gray-900 mb-1") do
              if @trace.spans.any?
                success_rate = ((@trace.spans.count - @trace.spans.errors.count).to_f / @trace.spans.count * 100).round(1)
                "#{success_rate}%"
              else
                "N/A"
              end
            end
            div(class: "text-sm text-gray-500") { "Operations completed" }
          end
        end

        if @trace.metadata.present?
          div(class: "mt-6 bg-white rounded-xl shadow-sm border border-gray-100") do
            div(class: "p-6 border-b border-gray-100") do
              div(class: "flex items-center gap-3") do
                div(class: "p-2 bg-gray-100 rounded-lg") do
                  i(class: "bi bi-code-square text-gray-600 text-lg")
                end
                h3(class: "text-lg font-semibold text-gray-900") { "Trace Metadata" }
              end
            end
            div(class: "p-6") do
              pre(class: "text-sm text-gray-700 bg-gray-50 rounded-lg p-4 overflow-auto border") do
                code { JSON.pretty_generate(@trace.metadata) }
              end
            end
          end
        end
      end

      def render_performance_insights
        return unless @trace.spans.any?

        div(class: "bg-white rounded-xl shadow-sm border border-gray-100") do
          div(class: "p-6 border-b border-gray-100") do
            div(class: "flex items-center gap-3") do
              div(class: "p-2 bg-indigo-100 rounded-lg") do
                i(class: "bi bi-lightning text-indigo-600 text-lg")
              end
              h3(class: "text-lg font-semibold text-gray-900") { "Performance Insights" }
            end
          end

          div(class: "p-6") do
            div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
              # Slowest span
              slowest = @trace.spans.max_by(&:duration_ms)
              if slowest
                div(class: "p-4 bg-red-50 rounded-lg border border-red-100") do
                  div(class: "flex items-center gap-2 mb-2") do
                    i(class: "bi bi-clock-history text-red-600")
                    span(class: "text-sm font-medium text-red-800") { "Slowest Operation" }
                  end
                  div(class: "text-sm text-red-700 mb-1 font-medium") { slowest.name }
                  div(class: "text-xs text-red-600") { format_duration(slowest.duration_ms) }
                end
              end

              # Most common span type
              span_types = @trace.spans.group_by(&:kind).transform_values(&:count)
              most_common = span_types.max_by { |_, count| count }
              if most_common
                div(class: "p-4 bg-blue-50 rounded-lg border border-blue-100") do
                  div(class: "flex items-center gap-2 mb-2") do
                    i(class: "bi bi-pie-chart text-blue-600")
                    span(class: "text-sm font-medium text-blue-800") { "Most Common Type" }
                  end
                  div(class: "text-sm text-blue-700 mb-1 font-medium") { most_common[0].capitalize }
                  div(class: "text-xs text-blue-600") { "#{most_common[1]} operations" }
                end
              end

              # Average duration
              avg_duration = @trace.spans.filter_map(&:duration_ms).sum.to_f / @trace.spans.count if @trace.spans.any?
              if avg_duration
                div(class: "p-4 bg-green-50 rounded-lg border border-green-100") do
                  div(class: "flex items-center gap-2 mb-2") do
                    i(class: "bi bi-speedometer text-green-600")
                    span(class: "text-sm font-medium text-green-800") { "Average Duration" }
                  end
                  div(class: "text-sm text-green-700 mb-1 font-medium") { format_duration(avg_duration) }
                  div(class: "text-xs text-green-600") { "Per operation" }
                end
              end
            end
          end
        end
      end

      def render_spans_hierarchy
        div(class: "bg-white rounded-xl shadow-sm border border-gray-100") do
          div(class: "p-6 border-b border-gray-100") do
            div(class: "flex items-center justify-between") do
              div(class: "flex items-center gap-3") do
                div(class: "p-2 bg-emerald-100 rounded-lg") do
                  i(class: "bi bi-diagram-2 text-emerald-600 text-lg")
                end
                div do
                  h3(class: "text-lg font-semibold text-gray-900") { "Execution Timeline" }
                  p(class: "text-sm text-gray-500") { "Hierarchical view of all operations and their relationships" }
                end
              end

              div(class: "flex gap-2") do
                span(class: "px-2 py-1 bg-gray-100 text-gray-600 text-xs rounded-md font-medium") { "#{@trace.spans.count} spans" }
                if @trace.spans.errors.any?
                  span(class: "px-2 py-1 bg-red-100 text-red-600 text-xs rounded-md font-medium") { "#{@trace.spans.errors.count} errors" }
                end
              end
            end
          end

          div(class: "p-6") do
            if @trace.spans.any?
              div(id: "span-hierarchy", class: "space-y-3") do
                render_span_tree(@trace.spans)
              end
            else
              div(class: "text-center py-12") do
                div(class: "p-4 bg-gray-100 rounded-full w-16 h-16 mx-auto mb-4 flex items-center justify-center") do
                  i(class: "bi bi-clock text-gray-400 text-2xl")
                end
                h4(class: "text-lg font-medium text-gray-900 mb-2") { "No spans found" }
                p(class: "text-gray-500") { "This trace doesn't contain any execution spans." }
              end
            end
          end
        end
      end

      def render_span_tree(spans, depth = 0)
        # Group spans by parent_id
        spans_by_parent = spans.group_by(&:parent_id)
        root_spans = spans_by_parent[nil] || []

        root_spans.each do |span|
          render_span_item(span, depth)

          # Render children recursively
          children = spans_by_parent[span.span_id] || []
          next unless children.any?

          Container(class: "ml-6 mt-2 space-y-2") do
            render_span_tree(children, depth + 1)
          end
        end
      end

      def render_span_item(span, depth = 0)
        div(class: "group relative bg-gray-50/50 hover:bg-white border border-gray-200/60 hover:border-gray-300 rounded-lg transition-all duration-200 hover:shadow-sm") do
          div(class: "p-4") do
            div(class: "flex items-start justify-between") do
              div(class: "flex-1") do
                div(class: "flex items-center gap-3 mb-2") do
                  render_modern_kind_badge(span.kind)
                  h4(class: "font-medium text-gray-900 text-sm") { span.name }
                  render_modern_status_badge(span.status) if span.status != "ok"
                end

                div(class: "flex items-center gap-4 text-xs text-gray-500 mb-3") do
                  div(class: "flex items-center gap-1") do
                    i(class: "bi bi-stopwatch")
                    span { format_duration(span.duration_ms) }
                  end
                  div(class: "flex items-center gap-1") do
                    i(class: "bi bi-clock")
                    span { span.start_time.strftime("%H:%M:%S.%L") }
                  end
                  if span.span_attributes && span.span_attributes.any?
                    div(class: "flex items-center gap-1") do
                      i(class: "bi bi-info-circle")
                      span { "#{span.span_attributes.keys.count} attributes" }
                    end
                  end
                end

                # Duration visualization
                if span.duration_ms&.positive?
                  div(class: "mb-3") do
                    div(class: "flex items-center justify-between text-xs text-gray-500 mb-1") do
                      span { "Execution time" }
                      span { "#{calculate_span_percentage(span).round(1)}% of trace" }
                    end
                    div(class: "w-full bg-gray-200 rounded-full h-1.5") do
                      div(
                        class: "h-1.5 rounded-full transition-all duration-300 #{span.status == 'error' ? 'bg-red-500' : 'bg-blue-500'}",
                        style: "width: #{[calculate_span_percentage(span), 100].min}%"
                      )
                    end
                  end
                end

                # Attributes (collapsible)
                if span.span_attributes && span.span_attributes.any?
                  details(class: "group/details") do
                    summary(class: "cursor-pointer text-xs text-blue-600 hover:text-blue-700 flex items-center gap-1 select-none") do
                      i(class: "bi bi-chevron-right group-open/details:rotate-90 transition-transform duration-200")
                      span { "View attributes (#{span.span_attributes.keys.count})" }
                    end
                    div(class: "mt-2 p-3 bg-gray-50 rounded border") do
                      div(class: "grid grid-cols-1 gap-2") do
                        span.span_attributes.each do |key, value|
                          next if %w[span_id trace_id parent_id].include?(key)

                          div(class: "flex flex-col gap-1") do
                            span(class: "text-xs font-medium text-gray-700") { key.humanize }
                            span(class: "text-xs text-gray-600 font-mono bg-white px-2 py-1 rounded border") { value.to_s.truncate(100) }
                          end
                        end
                      end
                    end
                  end
                end

                # Error details
                if span.error_details.present?
                  div(class: "mt-3 p-3 bg-red-50 border border-red-200 rounded-lg") do
                    div(class: "flex items-center gap-2 mb-2") do
                      i(class: "bi bi-exclamation-triangle text-red-600")
                      span(class: "text-sm font-medium text-red-800") { "Error Details" }
                    end
                    if span.error_details["exception_message"]
                      p(class: "text-sm text-red-700 mb-1") { span.error_details["exception_message"] }
                    end
                    if span.error_details["exception_type"]
                      p(class: "text-xs text-red-600") { "Type: #{span.error_details['exception_type']}" }
                    end
                  end
                end
              end

              # Quick stats sidebar
              div(class: "text-right flex flex-col items-end gap-1") do
                div(class: "px-2 py-1 bg-white rounded border text-xs font-medium text-gray-700") do
                  format_duration(span.duration_ms)
                end
                div(class: "text-xs text-gray-500") do
                  span.start_time.strftime("%H:%M:%S")
                end
              end
            end
          end
        end
      end

      def render_status_badge(status)
        classes = case status
                  when "ok", "completed"
                    "px-2 py-1 bg-green-100 text-green-800 border border-green-200"
                  when "error", "failed"
                    "px-2 py-1 bg-red-100 text-red-800 border border-red-200"
                  when "running"
                    "px-2 py-1 bg-yellow-100 text-yellow-800 border border-yellow-200"
                  else
                    "px-2 py-1 bg-gray-100 text-gray-800 border border-gray-200"
                  end

        icon = case status
               when "ok", "completed" then "check-circle-fill"
               when "error", "failed" then "x-circle-fill"
               when "running" then "arrow-clockwise"
               else "clock"
               end

        span(class: "#{classes} rounded-full text-xs font-medium flex items-center gap-1") do
          i(class: "bi bi-#{icon}")
          span { status.capitalize }
        end
      end

      def render_modern_status_badge(status)
        render_status_badge(status)
      end

      def render_kind_badge(kind)
        classes = case kind
                  when "agent"
                    "px-2 py-1 bg-blue-100 text-blue-800 border border-blue-200"
                  when "llm"
                    "px-2 py-1 bg-purple-100 text-purple-800 border border-purple-200"
                  when "tool"
                    "px-2 py-1 bg-green-100 text-green-800 border border-green-200"
                  when "handoff"
                    "px-2 py-1 bg-orange-100 text-orange-800 border border-orange-200"
                  else
                    "px-2 py-1 bg-gray-100 text-gray-800 border border-gray-200"
                  end

        icon = case kind
               when "agent" then "robot"
               when "llm" then "cpu"
               when "tool" then "wrench"
               when "handoff" then "arrow-left-right"
               else "gear"
               end

        span(class: "#{classes} rounded-full text-xs font-medium flex items-center gap-1") do
          i(class: "bi bi-#{icon}")
          span { kind.capitalize }
        end
      end

      def render_modern_kind_badge(kind)
        render_kind_badge(kind)
      end

      def calculate_span_percentage(span)
        return 0 unless span.duration_ms && @trace.duration_ms

        max_duration = @trace.duration_ms || 1
        [(span.duration_ms.to_f / max_duration * 100).round(2), 100].min
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
    end
    end
  end
end
