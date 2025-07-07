# frozen_string_literal: true

module OpenAIAgents
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
            Typography("Spans", variant: :heading, level: 1)
            Typography("Detailed view of all execution spans", variant: :muted)
          end
          
          preline_flex(align: :center, gap: 3) do
            preline_button(
              type: "button",
              onclick: "window.location.reload()",
              variant: :secondary,
              icon: "arrow-path"
            ) do
              "Refresh"
            end
          end
        end
      end

      def render_spans_table
        preline_card do
          if @spans.any?
            preline_table do
              preline_table_header do
                preline_table_row do
                  preline_table_cell("Name", header: true)
                  preline_table_cell("Kind", header: true)
                  preline_table_cell("Status", header: true)
                  preline_table_cell("Duration", header: true)
                  preline_table_cell("Trace", header: true)
                  preline_table_cell("Started", header: true)
                  preline_table_cell("Actions", header: true, align: :end)
                end
              end
              preline_table_body do
                @spans.each do |span|
                  render_span_row(span)
                end
              end
            end
          else
            preline_empty_state(
              icon: "clock",
              title: "No spans found",
              description: "No execution spans are available."
            )
          end
        end
      end

      def render_span_row(span)
        preline_table_row do
          preline_table_cell do
            preline_container do
              preline_text(span.name, variant: :heading, size: :sm)
              if span.attributes.present? && span.attributes['description']
                preline_text(truncate(span.attributes['description'], length: 60), variant: :muted, size: :sm)
              end
            end
          end
          
          preline_table_cell do
            render_kind_badge(span.kind)
          end
          
          preline_table_cell do
            render_status_badge(span.status)
          end
          
          preline_table_cell do
            format_duration(span.duration_ms)
          end
          
          preline_table_cell do
            if span.trace
              preline_link(trace_path(span.trace_id)) { span.trace.workflow_name }
            else
              preline_text(span.trace_id, variant: :muted, size: :sm)
            end
          end
          
          preline_table_cell do
            "#{time_ago_in_words(span.start_time)} ago"
          end
          
          preline_table_cell(align: :end) do
            preline_link(span_path(span.span_id)) { "View" }
          end
        end
      end

      def render_status_badge(status)
        variant = case status
                 when 'ok', 'completed' then :success
                 when 'error', 'failed' then :danger
                 when 'running' then :warning
                 else :secondary
                 end
        
        icon = case status
               when 'ok', 'completed' then "check-circle"
               when 'error', 'failed' then "x-circle"
               when 'running' then "arrow-path"
               else "clock"
               end
        
        preline_badge(status.capitalize, variant: variant, icon: icon)
      end

      def render_kind_badge(kind)
        variant = case kind
                 when 'agent' then :primary
                 when 'llm' then :info
                 when 'tool' then :success
                 when 'handoff' then :warning
                 else :secondary
                 end
        
        preline_badge(kind.capitalize, variant: variant, size: :sm)
      end

      def format_duration(ms)
        return "N/A" unless ms
        
        if ms < 1000
          "#{ms.round}ms"
        elsif ms < 60000
          "#{(ms / 1000.0).round(1)}s"
        else
          minutes = (ms / 60000).floor
          seconds = ((ms % 60000) / 1000.0).round(1)
          "#{minutes}m #{seconds}s"
        end
      end
    end
  end
end