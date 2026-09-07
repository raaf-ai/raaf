# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # A flat listing of spans, on the shared DataGrid.
      #
      class SpansList < BaseComponent
        # Columns from RAAF Tracing.dc.html.
        COLUMNS = [
          { label: "Span", span: 1.7 },
          { label: "Kind", span: 1.1 },
          { label: "Trace", span: 0.85 },
          { label: "Duration", span: 0.55, align: :right },
          { label: "Tokens", span: 0.75, align: :right },
          { label: "Status", span: 0.75 },
          { label: "Start", span: 0.7, align: :right }
        ].freeze

        def initialize(spans:, page: 1, per_page: 50)
          @spans = spans
          @page = page
          @per_page = per_page
        end

        def view_template
          render(Molecules::Panel.new(title: "Spans", icon: "layers")) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "clock-history", title: "No spans found",
                              text: "No execution spans are available yet." }
                   )) do |grid|
              @spans.each { |record| row(grid, record) }
            end
          end
        end

        private

        def row(grid, record)
          grid.row(href: trace_span_path(record.span_id, record.trace_id), cells: [
                     { value: display_name(record), primary: true },
                     { value: Atoms::KindBadge.new(record.kind) },
                     { value: record.trace&.workflow_name || record.trace_id, muted: true },
                     { value: Atoms::Mono.new(format_duration(record.duration_ms)), align: :right },
                     { value: Atoms::Mono.new(tokens_for(record), tone: :muted), align: :right },
                     { value: Atoms::StatusBadge.new(record.status) },
                     { value: Atoms::Mono.new(started(record), tone: :muted), align: :right }
                   ])
        end

        # Reads whichever shape the span recorded its tokens in — native
        # column or attributes payload — rather than one column that most
        # spans predate. See RAAF::Tracing::SpanUsage.
        def tokens_for(record)
          value = record.respond_to?(:total_token_count) ? record.total_token_count : nil
          value ? value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse : "—"
        end

        def display_name(record)
          record.respond_to?(:display_name) ? record.display_name : record.name
        end

        def started(record)
          time_ago(record.start_time)
        end
      end
    end
  end
end
