# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # DataGrid — the table every list screen uses.
        #
        # Owns the column template so the header and rows cannot disagree, and
        # derives it from each column's `span:` weight as `minmax(0, Nfr)`
        # tracks. Fixed pixel columns are deliberately not supported: they clip
        # the right-hand cells on narrow viewports.
        #
        # @example
        #   render(Organisms::DataGrid.new(columns: [
        #     { label: "Workflow", span: 3 },
        #     { label: "Spans", span: 1, align: :right },
        #     { label: "Status", span: 1 }
        #   ])) do |grid|
        #     traces.each do |trace|
        #       grid.row(href: trace_path(trace), cells: [
        #         { value: trace.workflow_name, primary: true },
        #         { value: trace.spans_count, align: :right },
        #         { value: Atoms::StatusBadge.new(trace.status) }
        #       ])
        #     end
        #   end
        #
        class DataGrid < Base
          # @param columns [Array<Hash>] :label, :span (fr weight, default 1), :align
          # @param empty [Hash, nil] arguments for Molecules::EmptyState
          def initialize(columns:, empty: nil, class: nil, **attrs)
            @columns = columns
            @empty = empty
            @rows = 0
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            body = capture { yield(self) if block }

            div(class: tokens("raaf-tbl", @class), role: "table", **@attrs) do
              render Molecules::TableHeader.new(columns: @columns, template: template)

              if @rows.zero? && @empty
                render Molecules::EmptyState.new(**@empty)
              else
                raw(safe(body))
              end
            end
          end

          # @param cells [Array<Hash>] one per column, in order
          def row(cells:, href: nil, **attrs)
            @rows += 1
            render Molecules::TableRow.new(cells: cells, template: template, href: href, **attrs)
          end

          private

          # `minmax(0, Nfr)` — the zero minimum is what lets a long value
          # truncate instead of pushing the row wider than its container.
          # 1.9 stays 1.9; 1.0 becomes 1 rather than "1.0fr".
          def format_weight(weight)
            weight.to_f == weight.to_i ? weight.to_i : weight
          end

          def template
            @template ||= @columns.map { |c| "minmax(0, #{format_weight(c.fetch(:span, 1))}fr)" }.join(" ")
          end
        end
      end
    end
  end
end
