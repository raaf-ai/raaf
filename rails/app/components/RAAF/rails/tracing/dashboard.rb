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
      include Components::Preline

      def initialize(overview_stats:, top_workflows:, recent_traces:, recent_errors: [], dashboard_url: '/raaf/traces', params: {})
        @overview_stats = overview_stats
        @top_workflows = top_workflows
        @recent_traces = recent_traces
        @recent_errors = recent_errors
        @dashboard_url = dashboard_url
        @params = params
      end

      def view_template
        render BaseLayout.new(title: "RAAF Tracing Dashboard") do
          Container(class: "space-y-6") do
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
        Flex(justify: :between, align: :center) do
          Container do
            Typography(tag: :h1, class: "text-3xl font-bold text-gray-900") { "Dashboard" }
            Typography(color: :muted) { "Monitor your Ruby AI Agents Factory performance and activity" }
          end

          Flex(align: :center, gap: 3) do
            Button(
              text: "Auto Refresh",
              type: "button",
              data: { action: "click->dashboard#enableAutoRefresh", refresh_interval: "30000" },
              variant: :secondary
            )
          end
        end
      end

      def render_filter_form
        render FilterForm.new(
          url: @dashboard_url,
          start_time: @params[:start_time] || 24.hours.ago.strftime("%Y-%m-%dT%H:%M"),
          end_time: @params[:end_time] || Time.current.strftime("%Y-%m-%dT%H:%M")
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
        Card do |card|
          card.header do
            Flex(justify: :between, align: :center) do
              Typography(tag: :h3, weight: :semibold) { "Top Workflows" }
              link_to("/raaf/tracing/traces") { "View All" }
            end
          end

          card.body do
            if @top_workflows.any?
              Table do
                TableHead do
                  TableRow do
                    TableCell("Workflow", header: true)
                    TableCell("Traces", header: true)
                    TableCell("Avg Duration", header: true)
                    TableCell("Success Rate", header: true)
                  end
                end
                TableBody do
                  @top_workflows.each do |workflow|
                    TableRow do
                      TableCell do
                        link_to("/raaf/tracing/traces?workflow=#{workflow[:workflow_name]}") do
                          workflow[:workflow_name]
                        end
                      end
                      TableCell(workflow[:trace_count])
                      TableCell(format_duration(workflow[:avg_duration] && (workflow[:avg_duration] * 1000)))
                      TableCell do
                        success_rate = workflow[:success_rate]
                        badge_variant = if success_rate > 95
                                          :success
                                        else
                                          (success_rate > 80 ? :warning : :danger)
                                        end
                        Badge("#{success_rate}%", variant: badge_variant)
                      end
                    end
                  end
                end
              end
            else
              Typography(color: :muted, align: :center) { "No workflows found in the selected time range." }
            end
          end
        end
      end

      def render_recent_activity
        Card do |card|
          card.header do
            Flex(justify: :between, align: :center) do
              Typography(tag: :h3) { "Recent Traces" }
              link_to("/raaf/tracing/traces") { "View All" }
            end
          end

          card.body do
            if @recent_traces.any?
              Stack(gap: 3) do
                @recent_traces.each do |trace|
                  Card(variant: :subtle, class: "p-4") do
                    Flex(justify: :between, align: :center) do
                      Container do
                        link_to("/raaf/tracing/traces/#{trace.trace_id}") do
                          trace.workflow_name
                        end
                        Typography(color: :muted, size: :sm) { "#{trace.started_at.strftime('%H:%M:%S')} • #{pluralize(trace.spans.count, 'span')}" }
                      end

                      Container(class: "text-right") do
                        render_status_badge(trace.status)
                        Typography(color: :muted, size: :sm) { format_duration(trace.duration_ms) }
                      end
                    end
                  end
                end
              end
            else
              Typography(color: :muted, align: :center) { "No recent traces found." }
            end
          end
        end
      end

      def render_recent_errors
        Card(variant: :danger) do |card|
          card.header do
            Flex(justify: :between, align: :center) do
              Flex(align: :center, gap: 2) do
                Icon("exclamation-triangle", size: :sm)
                Typography(tag: :h3, class: "text-red-800") { "Recent Errors" }
              end
              link_to("/raaf/tracing/errors", class: "text-sm text-red-600 hover:text-red-800") { "View All" }
            end
          end

          card.body do
            Stack(gap: 3) do
              @recent_errors.each do |span|
                Alert(variant: :danger) do
                  Flex(justify: :between, align: :start) do
                    Container do
                      Flex(align: :center, gap: 2) do
                        Typography(tag: :strong, size: :sm, class: "text-red-900") { span.name }
                        render_kind_badge(span.kind)
                      end
                      Typography(color: :muted, size: :sm, class: "text-red-700 mt-1") do
                        plain "Trace: "
                        link_to("/raaf/tracing/traces/#{span.trace_id}", class: "text-red-600 hover:text-red-800") do
                          span.trace&.workflow_name || span.trace_id
                        end
                      end
                      if span.error_details&.dig("exception_message")
                        Typography(color: :muted, size: :sm, class: "text-red-600 mt-2") do
                          truncate(span.error_details["exception_message"], length: 100)
                        end
                      end
                    end
                    Typography(color: :muted, size: :sm,
                                                                              class: "text-red-500") { "#{time_ago_in_words(span.start_time)} ago" }
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

        Badge(status.capitalize, variant: variant)
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
