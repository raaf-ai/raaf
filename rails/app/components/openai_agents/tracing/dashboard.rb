# frozen_string_literal: true

module RAAF
  module Tracing
    class Dashboard < Phlex::HTML
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::TimeAgoInWords
      include Phlex::Rails::Helpers::Pluralize
      include Phlex::Rails::Helpers::Truncate
      include Components::Preline

      def initialize(overview_stats:, top_workflows:, recent_traces:, recent_errors: [])
        @overview_stats = overview_stats
        @top_workflows = top_workflows
        @recent_traces = recent_traces
        @recent_errors = recent_errors
      end

      def template
        Container(class: "space-y-6") do
          render_header
          render_filter_form
          render_overview_metrics
          render_main_content
          render_recent_errors if @recent_errors.any?
        end
      end

      private

      def render_header
        Flex(justify: :between, align: :center) do
          Container do
            Typography("Dashboard", variant: :heading, level: 1, class: "text-3xl font-bold text-gray-900")
            Typography("Monitor your Ruby AI Agents Factory performance and activity", variant: :muted)
          end

          Flex(align: :center, gap: 3) do
            Button(
              type: "button",
              onclick: "enableAutoRefresh(30000)",
              variant: :secondary
            ) do
              "Auto Refresh"
            end
          end
        end
      end

      def render_filter_form
        render FilterForm.new(
          url: dashboard_path,
          start_time: params[:start_time] || 24.hours.ago.strftime("%Y-%m-%dT%H:%M"),
          end_time: params[:end_time] || Time.current.strftime("%Y-%m-%dT%H:%M")
        )
      end

      def render_overview_metrics
        Grid(cols: { md: 2, lg: 4 }, gap: 4, class: "mb-6") do
          render MetricCard.new(
            value: @overview_stats[:total_traces],
            label: "Total Traces",
            color: :blue
          )

          render MetricCard.new(
            value: @overview_stats[:completed_traces],
            label: "Completed",
            color: :green
          )

          render MetricCard.new(
            value: @overview_stats[:failed_traces],
            label: "Failed",
            color: :red
          )

          render MetricCard.new(
            value: @overview_stats[:running_traces],
            label: "Running",
            color: :yellow
          )
        end

        Grid(cols: { md: 2, lg: 4 }, gap: 4, class: "mb-6") do
          render MetricCard.new(
            value: @overview_stats[:total_spans],
            label: "Total Spans",
            color: :blue
          )

          render MetricCard.new(
            value: @overview_stats[:error_spans],
            label: "Error Spans",
            color: :gray
          )

          render MetricCard.new(
            value: format_duration(@overview_stats[:avg_trace_duration] && (@overview_stats[:avg_trace_duration] * 1000)),
            label: "Avg Duration",
            color: :blue
          )

          render MetricCard.new(
            value: "#{@overview_stats[:success_rate]}%",
            label: "Success Rate",
            color: if @overview_stats[:success_rate] > 95
                     :green
                   else
                     (@overview_stats[:success_rate] > 80 ? :yellow : :red)
                   end
          )
        end
      end

      def render_main_content
        Grid(cols: { lg: 2 }, gap: 6) do
          render_top_workflows
          render_recent_activity
        end
      end

      def render_top_workflows
        preline_card do
          preline_card_header do
            preline_flex(justify: :between, align: :center) do
              preline_heading("Top Workflows", level: 3)
              preline_link(traces_path) { "View All" }
            end
          end

          preline_card_body do
            if @top_workflows.any?
              preline_table do
                preline_table_header do
                  preline_table_row do
                    preline_table_cell("Workflow", header: true)
                    preline_table_cell("Traces", header: true)
                    preline_table_cell("Avg Duration", header: true)
                    preline_table_cell("Success Rate", header: true)
                  end
                end
                preline_table_body do
                  @top_workflows.each do |workflow|
                    preline_table_row do
                      preline_table_cell do
                        preline_link(traces_path(workflow: workflow[:workflow_name])) do
                          workflow[:workflow_name]
                        end
                      end
                      preline_table_cell(workflow[:trace_count])
                      preline_table_cell(format_duration(workflow[:avg_duration] && (workflow[:avg_duration] * 1000)))
                      preline_table_cell do
                        success_rate = workflow[:success_rate]
                        badge_variant = if success_rate > 95
                                          :success
                                        else
                                          (success_rate > 80 ? :warning : :danger)
                                        end
                        preline_badge("#{success_rate}%", variant: badge_variant)
                      end
                    end
                  end
                end
              end
            else
              preline_text("No workflows found in the selected time range.", variant: :muted, align: :center)
            end
          end
        end
      end

      def render_recent_activity
        preline_card do
          preline_card_header do
            preline_flex(justify: :between, align: :center) do
              preline_heading("Recent Traces", level: 3)
              preline_link(traces_path) { "View All" }
            end
          end

          preline_card_body do
            if @recent_traces.any?
              preline_stack(gap: 3) do
                @recent_traces.each do |trace|
                  preline_card(variant: :subtle, class: "p-4") do
                    preline_flex(justify: :between, align: :center) do
                      preline_container do
                        preline_link(trace_path(trace.trace_id)) do
                          trace.workflow_name
                        end
                        preline_text("#{trace.started_at.strftime("%H:%M:%S")} • #{pluralize(trace.spans.count, "span")}",
                                     variant: :muted, size: :sm)
                      end

                      preline_container(class: "text-right") do
                        render_status_badge(trace.status)
                        preline_text(format_duration(trace.duration_ms), variant: :muted, size: :sm)
                      end
                    end
                  end
                end
              end
            else
              preline_text("No recent traces found.", variant: :muted, align: :center)
            end
          end
        end
      end

      def render_recent_errors
        preline_card(variant: :danger) do
          preline_card_header do
            preline_flex(justify: :between, align: :center) do
              preline_flex(align: :center, gap: 2) do
                preline_icon("exclamation-triangle", size: :sm)
                preline_heading("Recent Errors", level: 3, class: "text-red-800")
              end
              preline_link(dashboard_errors_path, class: "text-sm text-red-600 hover:text-red-800") { "View All" }
            end
          end

          preline_card_body do
            preline_stack(gap: 3) do
              @recent_errors.each do |span|
                preline_alert(variant: :danger) do
                  preline_flex(justify: :between, align: :start) do
                    preline_container do
                      preline_flex(align: :center, gap: 2) do
                        preline_text(span.name, variant: :heading, size: :sm, class: "text-red-900")
                        render_kind_badge(span.kind)
                      end
                      preline_text("Trace: ", variant: :muted, size: :sm, class: "text-red-700 mt-1") do
                        preline_link(trace_path(span.trace_id), class: "text-red-600 hover:text-red-800") do
                          span.trace&.workflow_name || span.trace_id
                        end
                      end
                      if span.error_details&.dig("exception_message")
                        preline_text(truncate(span.error_details["exception_message"], length: 100),
                                     variant: :muted, size: :sm, class: "text-red-600 mt-2")
                      end
                    end
                    preline_text("#{time_ago_in_words(span.start_time)} ago", variant: :muted, size: :sm,
                                                                              class: "text-red-500")
                  end
                end
              end
            end
          end
        end
      end

      def render_status_badge(status)
        variant = case status
                  when "completed" then :success
                  when "failed" then :danger
                  when "running" then :warning
                  else :secondary
                  end

        preline_badge(status.capitalize, variant: variant)
      end

      def render_kind_badge(kind)
        variant = case kind
                  when "agent" then :primary
                  when "llm" then :info
                  when "tool" then :success
                  when "handoff" then :warning
                  else :secondary
                  end

        preline_badge(kind.capitalize, variant: variant, size: :sm)
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
