# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class TracesList < Phlex::HTML
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::TimeAgoInWords
      include Phlex::Rails::Helpers::Pluralize

      def initialize(traces:, stats: nil)
        @traces = traces
        @stats = stats
      end

      def view_template
        div(class: "container-fluid") do
          render_header
          render_stats if @stats
          render_traces_table
        end
      end

      private

      def render_header
        div(class: "d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom") do
          div do
            h1(class: "h2") { "Traces" }
            p(class: "text-muted") { "Monitor and analyze your agent execution traces" }
          end

          div(class: "btn-toolbar mb-2 mb-md-0") do
            div(class: "btn-group me-2") do
              a(
                href: "javascript:window.location.reload();",
                class: "btn btn-sm btn-outline-secondary",
                title: "Refresh"
              ) do
                i(class: "bi bi-arrow-clockwise me-1")
                plain "Refresh"
              end

              a(
                href: "/raaf/tracing/traces.json",
                class: "btn btn-sm btn-outline-secondary"
              ) do
                i(class: "bi bi-download me-1")
                plain "Export JSON"
              end
            end
          end
        end
      end

      def render_stats
        return unless @stats

        div(class: "row mb-4") do
          div(class: "col-md-3") do
            div(class: "card") do
              div(class: "card-body") do
                h6(class: "card-title text-muted") { "Total Traces" }
                h3(class: "mb-0") { @stats[:total_traces] }
              end
            end
          end

          div(class: "col-md-3") do
            div(class: "card") do
              div(class: "card-body") do
                h6(class: "card-title text-muted") { "Completed" }
                h3(class: "mb-0 text-success") { @stats[:completed_traces] }
              end
            end
          end

          div(class: "col-md-3") do
            div(class: "card") do
              div(class: "card-body") do
                h6(class: "card-title text-muted") { "Failed" }
                h3(class: "mb-0 text-danger") { @stats[:failed_traces] }
              end
            end
          end

          div(class: "col-md-3") do
            div(class: "card") do
              div(class: "card-body") do
                h6(class: "card-title text-muted") { "Success Rate" }
                h3(class: "mb-0") { "#{@stats[:success_rate]}%" }
              end
            end
          end
        end
      end

      def render_traces_table
        div(class: "card") do
          div(class: "card-body") do
            if @traces.any?
              div(class: "table-responsive") do
                table(class: "table table-sm") do
                  thead do
                    tr do
                      th { "Workflow" }
                      th { "Status" }
                      th { "Duration" }
                      th { "Spans" }
                      th { "Started" }
                      th(class: "text-end") { "Actions" }
                    end
                  end
                  tbody do
                    @traces.each do |trace|
                      render_trace_row(trace)
                    end
                  end
                end
              end
            else
              div(class: "text-center py-5") do
                i(class: "bi bi-diagram-3 display-4 text-muted")
                h3(class: "mt-3") { "No traces found" }
                p(class: "text-muted") { "No execution traces are available." }
              end
            end
          end
        end
      end

      def render_trace_row(trace)
        tr(data: { trace_id: trace.trace_id }) do
          td do
            div do
              strong { trace.workflow_name || "Unnamed Workflow" }
              br
              small(class: "text-muted") { trace.trace_id }
            end
          end

          td do
            render_status_badge(trace.status)
          end

          td do
            plain format_duration(trace.duration_ms)
          end

          td do
            span(class: "badge bg-secondary") { pluralize(trace.spans.count, "span") }
          end

          td do
            plain "#{time_ago_in_words(trace.started_at)} ago"
          end

          td(class: "text-end") do
            link_to("View", "/raaf/tracing/traces/#{trace.trace_id}", class: "btn btn-sm btn-outline-primary")
          end
        end
      end

      def render_status_badge(status)
        badge_class = case status
                      when "completed" then "bg-success"
                      when "failed" then "bg-danger"
                      when "running" then "bg-warning text-dark"
                      else "bg-secondary"
                      end

        span(class: "badge #{badge_class}") { status.to_s.capitalize }
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