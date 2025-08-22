# frozen_string_literal: true

module RAAF
  module Rails
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

      def view_template
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
            Typography(tag: :h1) { "Traces" }
            Typography(color: :muted) { "Monitor and analyze your agent execution traces" }
          end

          Flex(align: :center, gap: 3) do
            Button(
              id: "refresh-dashboard",
              variant: :secondary,
              icon: "arrow-path",
              title: "Refresh"
            )

            Button(
              href: "/raaf/tracing/traces.json",
              variant: :secondary,
              icon: "arrow-down-tray"
            ) do
              "Export JSON"
            end

            Flex(align: :center) do
              Checkbox(
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
          url: "/raaf/tracing/traces",
          search: params[:search],
          workflow: params[:workflow],
          status: params[:status],
          start_time: params[:start_time],
          end_time: params[:end_time]
        )
      end

      def render_stats
        Grid(cols: { md: 4 }, gap: 4, class: "mb-6") do
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
        Alert(
          id: "connection-status",
          variant: :info,
          class: "hidden mb-4"
        ) do
          Typography(class: "status-text") { "Connecting..." }
        end

        Card(id: "traces-table-container") do
          render_traces_table_content
        end
      end

      def render_traces_table_content
        if @traces.any?
          Table do
            TableHead do
              TableRow do
                TableCell("Workflow", header: true)
                TableCell("Status", header: true)
                TableCell("Duration", header: true)
                TableCell("Spans", header: true)
                TableCell("Started", header: true)
                TableCell("Actions", header: true, align: :end)
              end
            end
            TableBody do
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
        EmptyState(
          icon: "document-text",
          title: "No traces found",
          description: "Try adjusting your search criteria or time range."
        )
      end

      def render_trace_row(trace)
        TableRow(data: { trace_id: trace.trace_id }) do
          TableCell do
            Container do
              link_to("/raaf/tracing/traces/#{trace.trace_id}") { trace.workflow_name }
              Typography(color: :muted, size: :sm) { trace.trace_id }
            end
          end

          TableCell do
            render_status_badge(trace.status)
          end

          TableCell do
            format_duration(trace.duration_ms)
          end

          TableCell do
            Flex(align: :center) do
              Button(
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
              Typography(size: :sm) { pluralize(trace.spans.count, "span") }
            end
          end

          TableCell do
            time_ago_in_words(trace.started_at)
          end

          TableCell(align: :end) do
            link_to("/raaf/tracing/traces/#{trace.trace_id}") { "View" }
          end
        end

        # Collapsible spans row
        TableRow(id: "collapse-#{trace.trace_id}", class: "hs-collapse hidden") do
          TableCell(colspan: 6) do
            Card(variant: :subtle, class: "p-4") do
              Stack(gap: 2) do
                trace.spans.limit(5).each do |span|
                  Flex(justify: :between, align: :center) do
                    Flex(align: :center) do
                      render_kind_badge(span.kind)
                      Typography(size: :sm, class: "ml-2") { span.name }
                    end
                    Typography(color: :muted, size: :sm) { format_duration(span.duration_ms) }
                  end
                end

                if trace.spans.count > 5
                  Container(class: "text-center") do
                    link_to("/raaf/tracing/traces/#{trace.trace_id}") do
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
        Typography(color: :muted, class: "text-end mt-4", size: :sm) do
          Typography(id: "last-updated") { Time.current.strftime("%Y-%m-%d %H:%M:%S") }
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

        Badge(status.capitalize, variant: variant, icon: icon)
      end

      def render_kind_badge(kind)
        variant = case kind
                  when "agent" then :primary
                  when "llm" then :info
                  when "tool" then :success
                  when "handoff" then :warning
                  else :secondary
                  end

        Badge(kind.capitalize, variant: variant, size: :sm)
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
