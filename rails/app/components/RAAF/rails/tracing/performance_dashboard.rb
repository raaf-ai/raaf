# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # Performance: latency by span kind, and the slowest individual spans.
      #
      class PerformanceDashboard < BaseComponent
        SLOW_COLUMNS = [
          { label: "Span", span: 3 },
          { label: "Kind", span: 1 },
          { label: "Workflow", span: 2 },
          { label: "Duration", span: 1, align: :right },
          { label: "Started", span: 1, align: :right }
        ].freeze

        def initialize(performance_by_kind: {}, slowest_spans: [], performance_over_time: [], params: {})
          @performance_by_kind = performance_by_kind
          @slowest_spans = slowest_spans
          @performance_over_time = performance_over_time
          @params = params
        end

        def view_template
          kpis
          div(class: "raaf-split-main") do
            slowest_panel
            div(class: "raaf-split-side") { by_kind_panel }
          end
        end

        private

        def stats
          @performance_by_kind.values
        end

        def total_spans
          @total_spans ||= stats.sum { |s| s[:total_spans].to_i }
        end

        # Weighted by span count — a plain mean across kinds would let a rare
        # slow kind dominate the headline figure.
        def weighted_avg
          return 0 if total_spans.zero?

          stats.sum { |s| s[:avg_duration_ms].to_f * s[:total_spans].to_i } / total_spans
        end

        def worst_p95
          stats.map { |s| s[:p95_duration_ms].to_f }.max || 0
        end

        # The buckets behind the two headline figures, so a tile says whether
        # the number has been that all window or is one bad hour.
        def series_for(key)
          values = @performance_over_time.to_a.map { |bucket| bucket[key].to_f }
          values if values.length > 1
        end

        # Which hour a bar stands for, and what it was — the two things the
        # bars alone cannot say. Without them a spike is visible but not
        # locatable, which is the whole reason for looking at the tile.
        def series_tips_for(key)
          return [] unless series_for(key)

          @performance_over_time.to_a.map do |bucket|
            "#{bucket_at(bucket)} · #{reading(key, bucket)}"
          end
        end

        def bucket_at(bucket)
          at = bucket[:timestamp]
          at.respond_to?(:strftime) ? at.strftime("%b %-d %H:%M") : at.to_s
        end

        def reading(key, bucket)
          case key
          when :span_count
            errors = bucket[:error_count].to_i
            spans = "#{number(bucket[:span_count])} spans"
            errors.positive? ? "#{spans} · #{number(errors)} errored" : spans
          else
            "#{format_duration(bucket[key])} average"
          end
        end

        def kpis
          render Organisms::StatGrid.new(stats: [
                                           { label: "Spans", value: number(total_spans), tone: :accent,
                                             note: "in the selected range", icon: "layers",
                                             series: series_for(:span_count), series_tips: series_tips_for(:span_count) },
                                           { label: "Avg duration", value: format_duration(weighted_avg), tone: :warning,
                                             note: "weighted by span count", icon: "speedometer2",
                                             series: series_for(:avg_duration), series_tips: series_tips_for(:avg_duration) },
                                           { label: "Worst p95", value: format_duration(worst_p95), tone: :danger,
                                             note: "slowest kind at the 95th percentile", icon: "graph-up-arrow" },
                                           { label: "Kinds", value: @performance_by_kind.size, tone: :success,
                                             note: "span kinds observed", icon: "diagram-2" }
                                         ])
        end

        def by_kind_panel
          render(Molecules::Panel.new(title: "By kind", icon: "bar-chart")) do
            if @performance_by_kind.blank?
              render Molecules::EmptyState.new(icon: "bar-chart", title: "No timings")
            else
              slowest = worst_p95
              @performance_by_kind.each do |kind, stat|
                p95 = stat[:p95_duration_ms].to_f
                share = slowest.positive? ? (p95 / slowest * 100) : 0

                render Molecules::MeterRow.new(
                  name: kind.to_s,
                  value: format_duration(p95),
                  pct: share,
                  tone: (p95 >= slowest && slowest.positive? ? :bad : nil),
                  sub: "#{number(stat[:total_spans])} spans · median #{format_duration(stat[:median_duration_ms])}",
                  tip: "p95 #{format_duration(p95)} · #{share.round}% of the slowest kind " \
                       "(#{format_duration(slowest)})"
                )
              end
            end
          end
        end

        def slowest_panel
          render(Molecules::Panel.new(title: "Slowest spans", icon: "hourglass-split")) do
            render(Organisms::DataGrid.new(
                     columns: SLOW_COLUMNS,
                     empty: { icon: "speedometer2", title: "No spans",
                              text: "Nothing recorded in this range." }
                   )) do |grid|
              @slowest_spans.each { |span| row(grid, span) }
            end
          end
        end

        def row(grid, span)
          grid.row(href: trace_span_path(span.span_id, span.trace_id), cells: [
                     { value: span.name, primary: true },
                     { value: Atoms::KindBadge.new(span.kind) },
                     { value: span.trace&.workflow_name || span.trace_id, muted: true },
                     { value: Atoms::Mono.new(format_duration(span.duration_ms), tone: :warn), align: :right },
                     { value: Atoms::Mono.new(started(span), tone: :muted), align: :right }
                   ])
        end

        def started(span)
          time_ago(span.start_time)
        end

        def number(value)
          value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end
      end
    end
  end
end
