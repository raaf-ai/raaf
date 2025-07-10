# frozen_string_literal: true

module OpenAIAgents
  module Tracing
    class TraceDetail < Phlex::HTML
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::TimeAgoInWords
      include Phlex::Rails::Helpers::Pluralize
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
            Typography(@trace.workflow_name, variant: :heading, level: 1)
            Typography("Trace ID: #{@trace.trace_id}", variant: :muted)
          end

          preline_flex(align: :center, gap: 3) do
            preline_button(
              href: traces_path,
              variant: :secondary,
              icon: "arrow-left"
            ) do
              "Back to Traces"
            end
          end
        end
      end

      def render_trace_overview
        preline_card do
          preline_card_header do
            preline_heading("Trace Overview", level: 2)
          end

          preline_card_body do
            preline_grid(cols: { md: 2, lg: 4 }, gap: 4) do
              preline_card(variant: :subtle) do
                preline_text("Status", variant: :muted, size: :sm)
                preline_container(class: "mt-1") { render_status_badge(@trace.status) }
              end

              preline_card(variant: :subtle) do
                preline_text("Duration", variant: :muted, size: :sm)
                preline_text(format_duration(@trace.duration_ms), variant: :heading, size: :lg)
              end

              preline_card(variant: :subtle) do
                preline_text("Spans", variant: :muted, size: :sm)
                preline_text(@trace.spans.count.to_s, variant: :heading, size: :lg)
              end

              preline_card(variant: :subtle) do
                preline_text("Started", variant: :muted, size: :sm)
                preline_text(@trace.started_at.strftime("%H:%M:%S"), variant: :heading, size: :lg)
                preline_text("#{time_ago_in_words(@trace.started_at)} ago", variant: :muted, size: :sm)
              end
            end

            if @trace.metadata.present?
              preline_container(class: "mt-6") do
                preline_heading("Metadata", level: 3, size: :sm)
                preline_card(variant: :subtle, class: "mt-2 p-4 overflow-x-auto") do
                  preline_code_block(JSON.pretty_generate(@trace.metadata), language: "json")
                end
              end
            end
          end
        end
      end

      def render_spans_hierarchy
        preline_card do
          preline_card_header do
            preline_heading("Span Hierarchy", level: 2)
            preline_text("Execution flow and timing breakdown", variant: :muted)
          end

          preline_card_body do
            if @trace.spans.any?
              preline_container(id: "span-hierarchy", class: "space-y-2") do
                render_span_tree(@trace.spans)
              end
            else
              preline_empty_state(
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

          preline_container(class: "ml-6 mt-2 space-y-2") do
            render_span_tree(children, depth + 1)
          end
        end
      end

      def render_span_item(span, depth = 0)
        preline_card(variant: :subtle, class: "transition-colors hover:shadow-md") do
          preline_flex(align: :start, justify: :between) do
            preline_container(class: "flex-1") do
              preline_flex(align: :center, gap: 3) do
                render_kind_badge(span.kind)
                preline_text(span.name, variant: :heading, size: :sm)
                render_status_badge(span.status) if span.status != "ok"
              end

              if span.attributes.present?
                preline_container(class: "mt-2") do
                  span.attributes.each do |key, value|
                    next if %w[span_id trace_id parent_span_id].include?(key)

                    preline_text(class: "inline-block mr-4", size: :xs, variant: :muted) do
                      preline_text("#{key}: ", variant: :strong)
                      preline_text(value.to_s.truncate(50))
                    end
                  end
                end
              end

              if span.error_details.present?
                preline_alert(variant: :danger, class: "mt-2") do
                  preline_text("Error Details:", variant: :heading, size: :sm)
                  preline_container(class: "mt-1") do
                    if span.error_details["exception_message"]
                      preline_text(span.error_details["exception_message"], size: :sm)
                    end
                    if span.error_details["exception_type"]
                      preline_text("Type: #{span.error_details["exception_type"]}", size: :sm, variant: :muted)
                    end
                  end
                end
              end
            end

            preline_container(class: "text-right") do
              preline_text(format_duration(span.duration_ms), size: :sm)
              preline_text(span.start_time.strftime("%H:%M:%S.%L"), size: :xs, variant: :muted)
            end
          end

          # Duration bar
          if span.duration_ms && span.duration_ms > 0
            preline_progress_bar(
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
