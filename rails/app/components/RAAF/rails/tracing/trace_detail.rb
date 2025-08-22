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

      def initialize(trace:)
        @trace = trace
      end

      def template
        Container(class: "space-y-6") do
          render_header
          render_trace_overview
          render_spans_hierarchy
        end
      end

      private

      def render_header
        Flex(justify: :between, align: :center) do
          Container do
            Typography(tag: :h1, @trace.workflow_name)
            Typography(color: :muted, "Trace ID: #{@trace.trace_id}")
          end

          Flex(align: :center, gap: 3) do
            Button(
              href: "/raaf/tracing/traces",
              variant: :secondary,
              icon: "arrow-left"
            ) do
              "Back to Traces"
            end
          end
        end
      end

      def render_trace_overview
        Card do |card|
          card.header do
            Typography(tag: :h3, "Trace Overview")
          end

          card.body do
            Grid(cols: { md: 2, lg: 4 }, gap: 4) do
              Card(variant: :subtle) do
                Typography(color: :muted, "Status", size: :sm)
                Container(class: "mt-1") { render_status_badge(@trace.status) }
              end

              Card(variant: :subtle) do
                Typography(color: :muted, "Duration", size: :sm)
                Typography(format_duration(@trace.duration_ms), variant: :heading, size: :lg)
              end

              Card(variant: :subtle) do
                Typography(color: :muted, "Spans", size: :sm)
                Typography(tag: :strong, @trace.spans.count.to_s, size: :lg)
              end

              Card(variant: :subtle) do
                Typography(color: :muted, "Started", size: :sm)
                Typography(@trace.started_at.strftime("%H:%M:%S"), variant: :heading, size: :lg)
                Typography("#{time_ago_in_words(@trace.started_at)} ago", color: :muted, size: :sm)
              end
            end

            if @trace.metadata.present?
              Container(class: "mt-6") do
                Typography(tag: :h3, "Metadata", size: :sm)
                Card(variant: :subtle, class: "mt-2 p-4 overflow-x-auto") do
                  CodeBlock(JSON.pretty_generate(@trace.metadata), language: "json")
                end
              end
            end
          end
        end
      end

      def render_spans_hierarchy
        Card do |card|
          card.header do
            Typography(tag: :h3, "Span Hierarchy")
            Typography(color: :muted, "Execution flow and timing breakdown")
          end

          card.body do
            if @trace.spans.any?
              Container(id: "span-hierarchy", class: "space-y-2") do
                render_span_tree(@trace.spans)
              end
            else
              EmptyState(
                icon: "clock",
                title: "No spans found",
                description: "No spans found for this trace."
              )
            end
          end
        end
      end

      def render_span_tree(spans, depth = 0)
        # Group spans by parent_id
        spans_by_parent = spans.group_by(&:parent_span_id)
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
        Card(variant: :subtle, class: "transition-colors hover:shadow-md") do
          Flex(align: :start, justify: :between) do
            Container(class: "flex-1") do
              Flex(align: :center, gap: 3) do
                render_kind_badge(span.kind)
                Typography(tag: :strong, span.name, size: :sm)
                render_status_badge(span.status) if span.status != "ok"
              end

              if span.attributes.present?
                Container(class: "mt-2") do
                  span.attributes.each do |key, value|
                    next if %w[span_id trace_id parent_span_id].include?(key)

                    Typography(color: :muted, class: "inline-block mr-4", size: :xs) do
                      Typography(tag: :strong, "#{key}: ")
                      Typography(value.to_s.truncate(50))
                    end
                  end
                end
              end

              if span.error_details.present?
                Alert(variant: :danger, class: "mt-2") do
                  Typography(tag: :strong, "Error Details:", size: :sm)
                  Container(class: "mt-1") do
                    if span.error_details["exception_message"]
                      Typography(span.error_details["exception_message"], size: :sm)
                    end
                    if span.error_details["exception_type"]
                      Typography(color: :muted, "Type: #{span.error_details['exception_type']}", size: :sm)
                    end
                  end
                end
              end
            end

            Container(class: "text-right") do
              Typography(format_duration(span.duration_ms), size: :sm)
              Typography(span.start_time.strftime("%H:%M:%S.%L"), size: :xs, color: :muted)
            end
          end

          # Duration bar
          if span.duration_ms&.positive?
            ProgressBar(
              value: calculate_span_percentage(span),
              class: "mt-3"
            )
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
