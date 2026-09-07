# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # SpanWaterfall — every span of a trace against the trace's clock.
        #
        # Offsets and widths are computed here, from each span's start and
        # duration relative to the trace window, so a caller passes timings
        # rather than percentages and every row shares one scale.
        #
        # @example
        #   render Organisms::SpanWaterfall.new(
        #     spans: [{ kind: "tool", name: "crm_upsert", start_ms: 7100,
        #               duration_ms: 4002, level: 2, tone: :bad, id: "span_c41f" }],
        #     total_ms: 11_400, selected: "span_c41f"
        #   )
        #
        class SpanWaterfall < Base
          # A span too short to see still needs to be findable on the track.
          MIN_WIDTH_PCT = 0.6

          # @param spans [Array<Hash>] :id, :kind, :name, :start_ms, :duration_ms,
          #   :duration, :tokens, :level, :tone, :href
          # @param total_ms [Numeric, nil] the trace window; derived when omitted
          # @param selected [String, nil] id of the span the inspector is showing
          # @param empty [Hash, nil] arguments for Molecules::EmptyState
          def initialize(spans:, total_ms: nil, selected: nil, empty: nil, class: nil, **attrs)
            @spans = Array(spans)
            @total_ms = total_ms
            @selected = selected
            @empty = empty
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-waterfall", @class), **@attrs) do
              if @spans.empty?
                render Molecules::EmptyState.new(**(@empty || default_empty))
              else
                @spans.each { |span| row(span) }
              end
            end
          end

          private

          def default_empty
            { icon: "bar-chart-steps", title: "No spans recorded",
              text: "This trace finished without emitting any spans." }
          end

          # The window every bar is measured against. Zero would divide by zero
          # and a trace of one instant span legitimately has no width, so the
          # floor is one millisecond.
          def window
            @window ||= begin
              declared = @total_ms.to_f
              derived = @spans.map { |s| s[:start_ms].to_f + s[:duration_ms].to_f }.max.to_f
              [declared, derived, 1.0].max
            end
          end

          def origin
            @origin ||= @spans.map { |s| s[:start_ms].to_f }.min.to_f
          end

          def row(span)
            offset = ((span[:start_ms].to_f - origin) / window) * 100
            width = [(span[:duration_ms].to_f / window) * 100, MIN_WIDTH_PCT].max

            render Molecules::WaterfallRow.new(
              kind: span[:kind],
              name: span[:name],
              duration: span[:duration],
              tokens: span[:tokens],
              offset: offset,
              width: [width, 100 - offset].min,
              level: span[:level].to_i,
              tone: span[:tone],
              selected: selected?(span),
              href: span[:href]
            )
          end

          def selected?(span)
            @selected.present? && span[:id].to_s == @selected.to_s
          end
        end
      end
    end
  end
end
