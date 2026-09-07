# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # Monitor › Errors: one row per distinct failure, as RAAF Console.dc.html
      # draws it.
      #
      # The design gives this screen a single table of signatures and nothing
      # else. What it dropped was a KPI row counting the errors the table
      # already counts, and a second list of individual failures underneath —
      # which is the same data ungrouped, so the one noisy signature at the top
      # of the table filled it and hid everything else.
      #
      # A signature is the pair the {SpanRecord.error_signatures} rollup groups
      # on: exception class and message. The trend beside each is that
      # signature's count against the same length of time immediately before
      # the window, which is what says whether the fix is working.
      #
      class ErrorsDashboard < BaseComponent
        # Columns and fr weights taken from RAAF Console.dc.html.
        COLUMNS = [
          { label: "Error signature", span: 2.4 },
          { label: "Agent", span: 1.15 },
          { label: "Count", span: 0.65, align: :right },
          { label: "Trend", span: 0.75, align: :right },
          { label: "Last seen", span: 0.95, align: :right }
        ].freeze

        # @param signatures [Array<Hash>] rows from SpanRecord.error_signatures
        def initialize(signatures: [], params: {})
          @signatures = signatures.to_a
          @params = params
        end

        def view_template
          div(class: "raaf-page") do
            render(Organisms::Card.new(flush: true)) do
              render(Organisms::DataGrid.new(columns: COLUMNS, empty: empty_state)) do |grid|
                @signatures.each { |signature| row(grid, signature) }
              end
            end
          end
        end

        private

        def empty_state
          { icon: "check-circle", title: "Nothing failed",
            text: "Failures in the selected range are grouped here by exception." }
        end

        # To the newest span carrying the signature rather than to its trace:
        # the span detail is where the backtrace and the arguments that
        # produced it are, and the trace is one click on from there.
        def row(grid, signature)
          grid.row(href: trace_span_path(signature[:span_id], signature[:trace_id]), cells: [
                     { value: signature_cell(signature), primary: true },
                     { value: Atoms::Mono.new(signature[:agent], tone: :muted) },
                     { value: Atoms::Mono.new(number(signature[:count])), align: :right },
                     { value: trend_cell(signature[:trend]), align: :right },
                     { value: Atoms::Mono.new(time_ago(signature[:last_seen]), tone: :muted),
                       align: :right }
                   ])
        end

        def signature_cell(signature)
          Molecules::TitleMeta.new(signature[:exception], signature[:message],
                                   mono: true, tone: :bad)
        end

        # Rising is the only direction worth alarming about, so a fall is read
        # as good and a signature that has not moved stays quiet.
        def trend_cell(trend)
          return Atoms::Mono.new("new", tone: :warn) if trend.nil?
          return Atoms::Mono.new("— 0%", tone: :muted) if trend.zero?

          arrow = trend.positive? ? "▲" : "▼"
          Atoms::Mono.new("#{arrow} #{trend.abs}%", tone: trend.positive? ? :bad : :ok)
        end

        def number(value)
          value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end
      end
    end
  end
end
