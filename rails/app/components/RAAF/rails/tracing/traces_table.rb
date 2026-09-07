# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # The trace listing, on the shared DataGrid.
      #
      # Each trace's spans are previewed in a native <details> beneath its row;
      # the expander used to depend on Bootstrap JavaScript the dashboard never
      # loaded, so it had never worked.
      #
      class TracesTable < BaseComponent
        PREVIEW_LIMIT = 10

        # Columns and fr weights taken from RAAF Tracing.dc.html, which leads
        # with the trace id: it is the thing you copy into a log search, and
        # the workflow name repeats down the column in runs.
        COLUMNS = [
          { label: "Trace", span: 1.1 },
          { label: "Workflow", span: 1.7 },
          { label: "Status", span: 0.85 },
          { label: "Spans", span: 0.55, align: :right },
          { label: "Duration", span: 0.75, align: :right },
          { label: "Tokens", span: 0.75, align: :right },
          { label: "Cost", span: 0.7, align: :right },
          { label: "Started", span: 0.8, align: :right }
        ].freeze

        def initialize(traces:, params: {})
          @traces = traces
          @params = params
        end

        # The design's traces section opens straight on the column header — no
        # title bar, and no controls. Refresh, Export and Clear were mine, not
        # the design's; the page is the table, and it does not need announcing.
        def view_template
          render(Organisms::Card.new(flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "diagram-3", title: "No traces found",
                              text: "No traces match your current filters." }
                   )) do |grid|
              @traces.each { |trace| row(grid, trace) }
            end

            pagination if paginated?
          end
        end

        private

        def row(grid, trace)
          grid.row(href: tracing_trace_path(trace.trace_id), cells: [
                     { value: Atoms::Mono.new(short_id(trace.trace_id), tone: :accent) },
                     { value: trace.workflow_name.presence || "Unnamed workflow", primary: true },
                     { value: Atoms::StatusBadge.new(trace.status) },
                     { value: Atoms::Mono.new(trace.spans.count, tone: :muted), align: :right },
                     { value: Atoms::Mono.new(format_duration(trace.duration_ms)), align: :right },
                     { value: Atoms::Mono.new(tokens_for(trace), tone: :muted), align: :right },
                     { value: Atoms::Mono.new(cost_for(trace), tone: :muted), align: :right },
                     { value: Atoms::Mono.new(started(trace), tone: :muted), align: :right }
                   ])
        end

        # Totals for every trace on the page, in one query. Asking each trace
        # for its own totals would load all of its spans, so a 25-row page
        # would drag the whole span table through Ruby to print two numbers.
        def totals
          @totals ||= TraceRecord.token_totals_for(@traces.map(&:trace_id))
        end

        # An em dash rather than a zero: a trace whose spans recorded nothing
        # has an unknown bill, and "$0.000" would read as "this run was free".
        def tokens_for(trace)
          value = totals.dig(trace.trace_id, :tokens)
          value ? value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse : "—"
        end

        def cost_for(trace)
          value = totals.dig(trace.trace_id, :cost)
          value ? "$#{'%.3f' % value.to_f}" : "—"
        end

        # The full id is 32 hex characters; the leading eight identify a trace
        # in practice and are what the design prints.
        def short_id(id)
          id.to_s.delete_prefix("trace_").first(8)
        end

        def started(trace)
          return "—" unless trace.started_at

          time_ago(trace.started_at)
        end

        def paginated?
          @traces.respond_to?(:total_pages) && @traces.total_pages > 1
        end

        def pagination
          div(class: "raaf-panel-body--pad") do
            render Molecules::Pagination.new(
              page: @traces.current_page,
              total_pages: @traces.total_pages,
              total_count: @traces.total_count,
              per_page: @traces.limit_value,
              href: ->(page) { "#{tracing_traces_path}?#{@params.merge(page: page).to_query}" }
            )
          end
        end
      end
    end
  end
end
