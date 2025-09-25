# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class Dashboard < Phlex::HTML
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::TimeAgoInWords
      include Phlex::Rails::Helpers::Pluralize
      include Phlex::Rails::Helpers::Truncate
      include Phlex::Rails::Helpers::Routes

      def initialize(overview_stats:, top_workflows:, recent_traces:, recent_errors: [], dashboard_url: '/raaf/traces', params: {})
        @overview_stats = overview_stats
        @top_workflows = top_workflows
        @recent_traces = recent_traces
        @recent_errors = recent_errors
        @dashboard_url = dashboard_url
        @params = params
      end

      def view_template
        div(
          class: "container-fluid",
          data: {
            controller: "dashboard",
            "dashboard-channel-name-value": "RubyAIAgentsFactory::Tracing::TracesChannel",
            "dashboard-polling-interval-value": "5000",
            "dashboard-auto-refresh-value": "true"
          }
        ) do
          div(class: "space-y-6") do
            render_header
            render_filter_form
            render_overview_metrics
            render_main_content
            render_recent_errors if @recent_errors.any?
          end
        end
      end

      private

      def render_header
        div(class: "d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom") do
          div do
            h1(class: "h2") { "Dashboard" }
            p(class: "text-muted") { "Monitor your Ruby AI Agents Factory performance and activity" }
          end

          div(class: "btn-toolbar mb-2 mb-md-0") do
            div(class: "btn-group me-2") do
              button(
                type: "button",
                class: "btn btn-sm btn-outline-secondary",
                id: "auto-refresh-btn",
                data: { "dashboard-target": "refreshButton" }
              ) do
                i(class: "bi bi-arrow-clockwise me-1")
                plain "Auto Refresh"
              end
            end
          end
        end
      end

      def render_filter_form
        # Skip filter form for now, or implement inline
        div(class: "filter-form") do
          # Filter form would go here
        end
      end

      def render_overview_metrics
        div(class: "row mb-4") do
          div(class: "col-md-3") do
            div(class: "card card-metric border-primary") do
              div(class: "card-body") do
                div(
                  class: "metric-value text-primary",
                  data: { "dashboard-target": "totalTraces" }
                ) { @overview_stats[:total_traces].to_s }
                div(class: "metric-label") { "Total Traces" }
              end
            end
          end

          div(class: "col-md-3") do
            div(class: "card card-metric border-success") do
              div(class: "card-body") do
                div(class: "metric-value text-success") { @overview_stats[:completed_traces].to_s }
                div(class: "metric-label") { "Completed" }
              end
            end
          end

          div(class: "col-md-3") do
            div(class: "card card-metric border-danger") do
              div(class: "card-body") do
                div(class: "metric-value text-danger") { @overview_stats[:failed_traces].to_s }
                div(class: "metric-label") { "Failed" }
              end
            end
          end

          div(class: "col-md-3") do
            div(class: "card card-metric border-warning") do
              div(class: "card-body") do
                div(
                  class: "metric-value text-warning",
                  data: { "dashboard-target": "activeTraces" }
                ) { @overview_stats[:running_traces].to_s }
                div(class: "metric-label") { "Running" }
              end
            end
          end
        end

        div(class: "row mb-4") do
          div(class: "col-md-3") do
            div(class: "card card-metric border-info") do
              div(class: "card-body") do
                div(class: "metric-value text-info") { @overview_stats[:total_spans].to_s }
                div(class: "metric-label") { "Total Spans" }
              end
            end
          end

          div(class: "col-md-3") do
            div(class: "card card-metric border-secondary") do
              div(class: "card-body") do
                div(class: "metric-value text-secondary") { @overview_stats[:error_spans].to_s }
                div(class: "metric-label") { "Error Spans" }
              end
            end
          end

          div(class: "col-md-3") do
            div(class: "card card-metric") do
              div(class: "card-body") do
                div(class: "metric-value") { format_duration(@overview_stats[:avg_trace_duration] && (@overview_stats[:avg_trace_duration] * 1000)) }
                div(class: "metric-label") { "Avg Duration" }
              end
            end
          end

          div(class: "col-md-3") do
            div(class: "card card-metric") do
              div(class: "card-body") do
                div(class: "metric-value") { "#{@overview_stats[:success_rate]}%" }
                div(class: "metric-label") { "Success Rate" }
              end
            end
          end
        end
      end

      def render_main_content
        div(class: "row") do
          div(class: "col-md-6") do
            render_top_workflows
          end
          div(
            class: "col-md-6",
            data: { "dashboard-target": "tracesContainer" }
          ) do
            render_recent_activity
          end
        end
      end

      def render_top_workflows
        div(class: "card") do
          div(class: "card-header d-flex justify-content-between align-items-center") do
            h5(class: "card-title mb-0") { "Top Workflows" }
            link_to("View All", "/raaf/tracing/traces", class: "btn btn-sm btn-outline-primary")
          end

          div(class: "card-body") do
            if @top_workflows.any?
              div(class: "table-responsive") do
                table(class: "table table-sm") do
                  thead do
                    tr do
                      th { "Workflow" }
                      th { "Traces" }
                      th { "Avg Duration" }
                      th { "Success Rate" }
                    end
                  end
                  tbody do
                    @top_workflows.each do |workflow|
                      tr do
                        td do
                          link_to(workflow[:workflow_name], 
                                  "/raaf/tracing/traces?workflow=#{workflow[:workflow_name]}",
                                  class: "text-decoration-none")
                        end
                        td { workflow[:trace_count].to_s }
                        td { format_duration(workflow[:avg_duration] && (workflow[:avg_duration] * 1000)) }
                        td do
                          success_rate = workflow[:success_rate]
                          badge_class = if success_rate > 95
                                          "bg-success"
                                        else
                                          (success_rate > 80 ? "bg-warning" : "bg-danger")
                                        end
                          span(class: "badge #{badge_class}") { "#{success_rate}%" }
                        end
                      end
                    end
                  end
                end
              end
            else
              p(class: "text-muted") { "No workflows found in the selected time range." }
            end
          end
        end
      end

      def render_recent_activity
        div(class: "card") do
          div(class: "card-header d-flex justify-content-between align-items-center") do
            h5(class: "card-title mb-0") { "Recent Traces" }
            link_to("View All", "/raaf/tracing/traces", class: "btn btn-sm btn-outline-primary")
          end

          div(class: "card-body") do
            if @recent_traces.any?
              @recent_traces.each do |trace|
                div(class: "d-flex justify-content-between align-items-center mb-2 p-2 bg-light rounded") do
                  div do
                    link_to(trace.workflow_name, 
                            "/raaf/tracing/traces/#{trace.trace_id}",
                            class: "fw-bold text-decoration-none")
                    br
                    small(class: "text-muted") do
                      plain "#{trace.started_at.strftime('%H:%M:%S')} • "
                      plain pluralize(trace.spans.count, 'span')
                    end
                  end

                  div(class: "text-end") do
                    # Get skip reasons summary for traces that have skipped spans
                    skip_reason = if trace.respond_to?(:skip_reasons_summary)
                                    begin
                                      trace.skip_reasons_summary
                                    rescue StandardError => e
                                      Rails.logger.warn "Failed to get skip_reasons_summary for trace #{trace.trace_id}: #{e.message}"
                                      nil
                                    end
                                  end

                    render_status_badge(trace.status, skip_reason: skip_reason)
                    br
                    small(class: "text-muted") { format_duration(trace.duration_ms) }
                  end
                end
              end
            else
              p(class: "text-muted") { "No recent traces found." }
            end
          end
        end
      end

      def render_recent_errors
        div(class: "row mt-4") do
          div(class: "col-12") do
            div(class: "card") do
              div(class: "card-header d-flex justify-content-between align-items-center") do
                h5(class: "card-title mb-0 text-danger") do
                  i(class: "bi bi-exclamation-triangle me-2")
                  plain "Recent Errors"
                end
                link_to("View All", "/raaf/tracing/dashboard/errors", class: "btn btn-sm btn-outline-danger")
              end

              div(class: "card-body") do
                @recent_errors.each do |span|
                  div(class: "alert alert-danger mb-2", role: "alert") do
                    div(class: "d-flex justify-content-between align-items-start") do
                      div do
                        strong { span.name }
                        plain " "
                        render_kind_badge(span.kind)
                        br
                        small(class: "text-muted") do
                          plain "Trace: "
                          link_to(span.trace&.workflow_name || span.trace_id,
                                  "/raaf/tracing/traces/#{span.trace_id}",
                                  class: "text-muted")
                        end
                        if span.error_details&.dig("exception_message")
                          br
                          small { truncate(span.error_details["exception_message"], length: 100) }
                        end
                      end
                      small(class: "text-muted") { "#{time_ago_in_words(span.start_time)} ago" }
                    end
                  end
                end
              end
            end
          end
        end
      end

      def render_status_badge(status, skip_reason: nil)
        render RAAF::Rails::Tracing::SkippedBadgeTooltip.new(status: status, skip_reason: skip_reason)
      end

      def render_kind_badge(kind)
        badge_class = case kind
                      when "agent" then "bg-primary"
                      when "llm" then "bg-info"
                      when "tool" then "bg-success"
                      when "handoff" then "bg-warning text-dark"
                      else "bg-secondary"
                      end

        span(class: "badge #{badge_class}") { kind.to_s.capitalize }
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
