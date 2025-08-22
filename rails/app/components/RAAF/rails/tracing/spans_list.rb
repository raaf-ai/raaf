# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class SpansList < Phlex::HTML
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::TimeAgoInWords
      include Phlex::Rails::Helpers::Truncate
      include Components::Preline

      def initialize(spans:)
        @spans = spans
      end

      def template
        Container(class: "space-y-6") do
          render_header
          render_spans_table
        end
      end

      private

      def render_header
        Flex(align: :center, justify: :between) do
          Container do
            Typography(tag: :h1, "Spans")
            Typography(color: :muted, "Detailed view of all execution spans")
          end

          Flex(align: :center, gap: 3) do
            Button(
              type: "button",
              data: { action: "click->window#reload" },
              variant: :secondary,
              icon: "arrow-path"
            ) do
              "Refresh"
            end
          end
        end
      end

      def render_spans_table
        Card do
          if @spans.any?
            Table do
              TableHead do
                TableRow do
                  TableCell("Name", header: true)
                  TableCell("Kind", header: true)
                  TableCell("Status", header: true)
                  TableCell("Duration", header: true)
                  TableCell("Trace", header: true)
                  TableCell("Started", header: true)
                  TableCell("Actions", header: true, align: :end)
                end
              end
              TableBody do
                @spans.each do |span|
                  render_span_row(span)
                end
              end
            end
          else
            EmptyState(
              icon: "clock",
              title: "No spans found",
              description: "No execution spans are available."
            )
          end
        end
      end

      def render_span_row(span)
        TableRow do
          TableCell do
            Container do
              Typography(tag: :strong, span.name, size: :sm)
              if span.attributes.present? && span.attributes["description"]
                Typography(truncate(span.attributes["description"], length: 60), color: :muted, size: :sm)
              end
            end
          end

          TableCell do
            render_kind_badge(span.kind)
          end

          TableCell do
            render_status_badge(span.status)
          end

          TableCell do
            format_duration(span.duration_ms)
          end

          TableCell do
            if span.trace
              link_to(trace_path(span.trace_id)) { span.trace.workflow_name }
            else
              Typography(color: :muted, span.trace_id, size: :sm)
            end
          end

          TableCell do
            "#{time_ago_in_words(span.start_time)} ago"
          end

          TableCell(align: :end) do
            link_to(span_path(span.span_id)) { "View" }
          end
        end
      end

      def render_status_badge(status)
        variant = case status
                  when "ok", "completed" then :success
                  when "error", "failed" then :danger
                  when "running" then :warning
                  else :secondary
                  end

        icon = case status
               when "ok", "completed" then "check-circle"
               when "error", "failed" then "x-circle"
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
