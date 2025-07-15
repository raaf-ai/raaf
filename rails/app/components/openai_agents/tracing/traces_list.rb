# frozen_string_literal: true

module RubyAIAgentsFactory
  module Tracing
    class TracesList < Phlex::HTML
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::TimeAgoInWords
      include Phlex::Rails::Helpers::Pluralize
      include Components::Preline

      def initialize(traces:, stats: nil)
        @traces = traces
        @stats = stats
      end

      def template
        Container(class: "space-y-6") do
          render_header
          render_filter_form
          render_stats if @stats
          render_traces_table
          render_last_updated
        end
      end

      private

      def render_header
        Flex(justify: :between, align: :center) do
          Container do
            Typography("Traces", variant: :heading, level: 1)
            Typography("Monitor and analyze your agent execution traces", variant: :muted)
          end

          preline_flex(align: :center, gap: 3) do
            preline_button(
              id: "refresh-dashboard",
              variant: :secondary,
              icon: "arrow-path",
              title: "Refresh"
            )

            preline_button(
              href: traces_path(format: :json),
              variant: :secondary,
              icon: "arrow-down-tray"
            ) do
              "Export JSON"
            end

            preline_flex(align: :center) do
              preline_checkbox(
                id: "auto-refresh-toggle",
                checked: true,
                label: "Auto-refresh"
              )
            end
          end
        end
      end

      def render_filter_form
        render FilterForm.new(
          url: traces_path,
          search: params[:search],
          workflow: params[:workflow],
          status: params[:status],
          start_time: params[:start_time],
          end_time: params[:end_time]
        )
      end

      def render_stats
        preline_grid(cols: { md: 4 }, gap: 4, class: "mb-6") do
          render MetricCard.new(
            value: @stats[:total],
            label: "Total",
            color: :blue
          )

          render MetricCard.new(
            value: @stats[:completed],
            label: "Completed",
            color: :green
          )

          render MetricCard.new(
            value: @stats[:failed],
            label: "Failed",
            color: :red
          )

          render MetricCard.new(
            value: @stats[:running],
            label: "Running",
            color: :yellow
          )
        end
      end

      def render_traces_table
        # Connection Status
        preline_alert(
          id: "connection-status",
          variant: :info,
          class: "hidden mb-4"
        ) do
          preline_text("Connecting...", class: "status-text")
        end

        preline_card(id: "traces-table-container") do
          render_traces_table_content
        end
      end

      def render_traces_table_content
        if @traces.any?
          preline_table do
            preline_table_header do
              preline_table_row do
                preline_table_cell("Workflow", header: true)
                preline_table_cell("Status", header: true)
                preline_table_cell("Duration", header: true)
                preline_table_cell("Spans", header: true)
                preline_table_cell("Started", header: true)
                preline_table_cell("Actions", header: true, align: :end)
              end
            end
            preline_table_body do
              @traces.each do |trace|
                render_trace_row(trace)
              end
            end
          end
        else
          render_empty_state
        end
      end

      def render_empty_state
        preline_empty_state(
          icon: "document-text",
          title: "No traces found",
          description: "Try adjusting your search criteria or time range."
        )
      end

      def render_trace_row(trace)
        preline_table_row(data: { trace_id: trace.trace_id }) do
          preline_table_cell do
            preline_container do
              preline_link(trace_path(trace.trace_id)) { trace.workflow_name }
              preline_text(trace.trace_id, variant: :muted, size: :sm)
            end
          end

          preline_table_cell do
            render_status_badge(trace.status)
          end

          preline_table_cell do
            format_duration(trace.duration_ms)
          end

          preline_table_cell do
            preline_flex(align: :center) do
              preline_button(
                type: "button",
                variant: :ghost,
                size: :sm,
                icon: "chevron-right",
                class: "toggle-spans mr-2",
                data: {
                  "hs-collapse": "#collapse-#{trace.trace_id}",
                  "hs-collapse-toggle": "#collapse-#{trace.trace_id}"
                }
              )
              preline_text(pluralize(trace.spans.count, "span"), size: :sm)
            end
          end

          preline_table_cell do
            time_ago_in_words(trace.started_at)
          end

          preline_table_cell(align: :end) do
            preline_link(trace_path(trace.trace_id)) { "View" }
          end
        end

        # Collapsible spans row
        preline_table_row(id: "collapse-#{trace.trace_id}", class: "hs-collapse hidden") do
          preline_table_cell(colspan: 6) do
            preline_card(variant: :subtle, class: "p-4") do
              preline_stack(gap: 2) do
                trace.spans.limit(5).each do |span|
                  preline_flex(justify: :between, align: :center) do
                    preline_flex(align: :center) do
                      render_kind_badge(span.kind)
                      preline_text(span.name, size: :sm, class: "ml-2")
                    end
                    preline_text(format_duration(span.duration_ms), variant: :muted, size: :sm)
                  end
                end

                if trace.spans.count > 5
                  preline_container(class: "text-center") do
                    preline_link(trace_path(trace.trace_id)) do
                      "View all #{trace.spans.count} spans"
                    end
                  end
                end
              end
            end
          end
        end
      end

      def render_last_updated
        preline_text(class: "text-end mt-4", variant: :muted, size: :sm) do
          preline_text(Time.current.strftime("%Y-%m-%d %H:%M:%S"), id: "last-updated")
        end
      end

      def render_status_badge(status)
        variant = case status
                  when "completed" then :success
                  when "failed" then :danger
                  when "running" then :warning
                  else :secondary
                  end

        icon = case status
               when "completed" then "check-circle"
               when "failed" then "x-circle"
               when "running" then "arrow-path"
               else "clock"
               end

        preline_badge(status.capitalize, variant: variant, icon: icon)
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
