# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class SpansList < Phlex::HTML
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::TimeAgoInWords
      include Phlex::Rails::Helpers::Truncate

      def initialize(spans:, page: 1, per_page: 50)
        @spans = spans
        @page = page
        @per_page = per_page
      end

      def view_template
        div(class: "container-fluid") do
          render_header
          render_spans_table
        end
      end

      private

      def render_header
        div(class: "d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom") do
          div do
            h1(class: "h2") { "Spans" }
            p(class: "text-muted") { "Detailed view of all execution spans" }
          end

          div(class: "btn-toolbar mb-2 mb-md-0") do
            div(class: "btn-group me-2") do
              a(
                href: "javascript:window.location.reload();",
                class: "btn btn-sm btn-outline-secondary"
              ) do
                i(class: "bi bi-arrow-clockwise me-1")
                plain "Refresh"
              end
            end
          end
        end
      end

      def render_spans_table
        div(class: "card") do
          div(class: "card-body") do
            if @spans.any?
              div(class: "table-responsive") do
                table(class: "table table-sm") do
                  thead do
                    tr do
                      th { "Name" }
                      th { "Kind" }
                      th { "Status" }
                      th { "Duration" }
                      th { "Trace" }
                      th { "Started" }
                      th(class: "text-end") { "Actions" }
                    end
                  end
                  tbody do
                    @spans.each do |span|
                      render_span_row(span)
                    end
                  end
                end
              end
            else
              div(class: "text-center py-5") do
                i(class: "bi bi-clock display-4 text-muted")
                h3(class: "mt-3") { "No spans found" }
                p(class: "text-muted") { "No execution spans are available." }
              end
            end
          end
        end
      end

      def render_span_row(span)
        tr do
          td do
            div do
              strong { span.name }
              if span.span_attributes.present? && span.span_attributes["description"]
                br
                small(class: "text-muted") { truncate(span.span_attributes["description"], length: 60) }
              end
            end
          end

          td do
            render_kind_badge(span.kind)
          end

          td do
            render_status_badge(span.status)
          end

          td do
            plain format_duration(span.duration_ms)
          end

          td do
            if span.trace
              link_to(span.trace.workflow_name, "/raaf/tracing/traces/#{span.trace_id}", class: "text-decoration-none")
            else
              small(class: "text-muted") { span.trace_id }
            end
          end

          td do
            plain "#{time_ago_in_words(span.start_time)} ago"
          end

          td(class: "text-end") do
            link_to("View", "/raaf/tracing/spans/#{span.span_id}", class: "btn btn-sm btn-outline-primary")
          end
        end
      end

      def render_status_badge(status)
        badge_class = case status
                      when "ok", "completed" then "bg-success"
                      when "error", "failed" then "bg-danger"
                      when "running" then "bg-warning text-dark"
                      else "bg-secondary"
                      end

        span(class: "badge #{badge_class}") { status.to_s.capitalize }
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
