# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # The span listing: one flat table, as the design draws it.
      #
      # There used to be a Hierarchy view beside it, with a tab pair to switch.
      # The design has neither, and the parent/child structure it showed is
      # better answered by a trace's waterfall, which draws one run's tree on
      # a shared time scale instead of interleaving every trace's.
      #
      class SpansIndex < BaseComponent
        # @param kind_counts [Hash] span counts per kind for the filter rail,
        #   taken before the kind filter so the chips read as facets
        # @param type_counts [Hash] the same counts split by `component.type`,
        #   keyed [kind, type]; a kind holding more than one type is offered as
        #   its types instead of as itself
        def initialize(spans:, paginated_spans:, kind_counts: {}, type_counts: {}, params: {})
          @spans = spans
          @paginated_spans = paginated_spans
          @kind_counts = kind_counts || {}
          @type_counts = type_counts || {}
          @params = params
        end

        # The design opens this screen on the kind rail. The explainer card
        # that used to sit above it — three icons and a sentence about the
        # chevrons — cost more height than the tree it described, so its two
        # real controls moved into the actions row and the rest is gone.
        # Hierarchy and List are two views of one set of spans, so they are
        # tabs — the same underline tabs Flows uses for its three views, which
        # is the design's own pattern for this. They are not chrome: without
        # them one of the two views has no way in.
        def view_template
          div(class: "raaf-page") do
            filters
            active_filters
            body
          end
        end

        private

        # Columns and fr weights taken from RAAF Tracing.dc.html.
        def columns
          [
            { label: "Span", span: 1.9 },
            { label: "Kind", span: 0.8 },
            { label: "Trace", span: 1.1 },
            { label: "Duration", span: 0.7, align: :right },
            { label: "Tokens", span: 0.7, align: :right },
            { label: "Status", span: 0.75, align: :right },
            { label: "Start", span: 0.7, align: :right }
          ]
        end

        # The design filters this screen by kind, on a rail of pills that carry
        # their own counts — the count is the reason to click one, so a chip
        # without it is a guess.
        def filters
          render Molecules::FilterBar.new(chips: kind_chips, grouped: false, outlined: true,
                                          query: @params[:search], action: tracing_spans_path,
                                          name: "search", placeholder: "Search spans…",
                                          carry: carried_filters.except(:search))
        end

        # The narrowings the rail cannot show, as pills that remove
        # themselves.
        #
        # This screen honours `search` and `status`, and those are exactly how
        # its two main entry points arrive: an Agents row links here with
        # `search=<agent name>`, a Tools card with `search=<tool name>`. The
        # reader landed on a filtered list with the term printed nowhere and
        # no way to drop it — the empty state offers a reset, so the only way
        # to find the filter was to narrow it until nothing matched.
        def active_filters
          applied = applied_filters
          return if applied.empty?

          div(class: "raaf-filterbar") do
            div(class: "raaf-chip-rail raaf-chip-rail--loose raaf-chip-rail--outlined") do
              applied.each { |filter| render Atoms::Chip.new(**filter) }
              render Atoms::Chip.new(label: "Clear all", href: spans_filter_path(clearable))
            end
          end
        end

        # Ordered so the pills read the way the reader arrived: the search
        # term first, since that is what a link from Agents or Tools sets.
        def applied_filters
          %i[search status].filter_map do |key|
            value = @params[key]
            next if value.blank?

            { label: "#{key}: #{value} ✕", active: true,
              href: spans_filter_path(key => nil) }
          end
        end

        def clearable
          { search: nil, status: nil }
        end

        def kind_chips
          all = [{ label: "All", active: @params[:kind].blank? && @params[:type].blank?,
                   count: @kind_counts.values.sum.nonzero?,
                   href: spans_filter_path(kind: nil, type: nil) }]

          all + facets.sort_by { |facet| -facet[:count] }.map { |facet| chip(facet) }
        end

        # `kind` is a container for some of what it holds: every span this
        # console has ever shown under "component" is really a search or an
        # ecosystem lookup, and a rail that only offers the container cannot
        # narrow to either. So a kind is offered as its `component.type`s
        # wherever those name something the kind does not.
        #
        # Two types are not subdivisions and are skipped: one that merely
        # repeats its kind (job/job), and one that carries the name of another
        # kind — a handful of llm spans are typed "agent", and a second chip
        # reading "agent" would describe neither set.
        #
        # The parent chip survives only when the split leaves something over,
        # since a parent whose children already account for all of it is the
        # same filter under a longer name.
        def facets
          @kind_counts.flat_map do |kind, count|
            subtypes = subtypes_for(kind)
            residual = count - subtypes.values.sum

            chips = subtypes.map do |type, type_count|
              { kind: kind, type: type, label: type, count: type_count }
            end
            chips << { kind: kind, type: nil, label: kind, count: count } if residual.positive?
            chips
          end
        end

        def subtypes_for(kind)
          @type_counts.filter_map do |(facet_kind, type), count|
            next unless facet_kind.to_s == kind.to_s
            next if type.blank? || type.to_s == kind.to_s
            next if @kind_counts.key?(type.to_s)

            [type, count]
          end.to_h
        end

        # The dot stays the kind's colour even when the chip is named after a
        # type: the row's badge will say "component", and the two should not
        # look like different things.
        def chip(facet)
          { label: facet[:label], count: facet[:count], dot: facet[:kind],
            active: active_facet?(facet),
            href: spans_filter_path(kind: facet[:kind], type: facet[:type]) }
        end

        def active_facet?(facet)
          @params[:kind].to_s == facet[:kind].to_s && @params[:type].to_s == facet[:type].to_s
        end

        # Keeps the view, search, status and the topbar's range while
        # swapping the kind — a chip that silently reset the window would
        # change the counts it just quoted.
        def spans_filter_path(overrides)
          tracing_spans_path(carried_filters.merge(overrides).compact.reject { |_, v| v.to_s.empty? })
        end

        def carried_filters
          { kind: @params[:kind], type: @params[:type], status: @params[:status],
            search: @params[:search], view: @params[:view], range: @params[:range] }
        end

        def body
          return empty_state unless @spans.any?

          render(Organisms::Card.new(flush: true)) do
            table
            pagination if paginated?
          end
        end

        def table
          render(Organisms::DataGrid.new(columns: columns)) do |grid|
            @spans.each { |record| row(grid, record) }
          end
        end

        def row(grid, record)
          grid.row(href: trace_span_path(record.span_id, record.trace_id), cells: [
                     { value: Molecules::TitleMeta.new(display_name(record), subject(record)),
                       primary: true },
                     { value: Atoms::KindBadge.new(record.kind) },
                     { value: Atoms::Mono.new(truncate_id(record.trace_id), tone: :accent) },
                     { value: Atoms::Mono.new(format_duration(record.duration_ms)), align: :right },
                     { value: Atoms::Mono.new(tokens_for(record), tone: :muted), align: :right },
                     { value: Atoms::StatusBadge.new(record.status), align: :right },
                     { value: Atoms::Mono.new(started_at(record), tone: :muted), align: :right }
                   ])
        end

        # Every emitter records usage under a different key, and only one of
        # them ever nested it under "usage" — which is what this used to read,
        # so the column was empty for every span in the table. SpanUsage knows
        # all of the shapes, including the native columns.
        def tokens_for(record)
          count = record.respond_to?(:total_token_count) ? record.total_token_count : nil

          return "—" unless count

          count >= 1000 ? "#{(count / 1000.0).round(1)}k" : count.to_s
        end

        def display_name(record)
          record.respond_to?(:display_name) ? record.display_name : record.name
        end

        # What the span was about, under its name. Three thousand rows reading
        # "Ai::SearchProviders::Google" are one row repeated; the query is what
        # makes them different spans.
        def subject(record)
          record.display_subject if record.respond_to?(:display_subject)
        end

        def started_at(record)
          time_ago(record.start_time)
        end

        def trace_link(record)
          if record.trace
            a(href: tracing_trace_path(record.trace_id)) { record.trace.workflow_name || record.trace_id }
          else
            render Atoms::Text.new(record.trace_id, as: :span, size: :sm, tone: :muted, mono: true)
          end
        end

        def skip_reason(record)
          return nil unless %w[cancelled skipped].include?(record.status) && record.respond_to?(:skip_reason)

          record.skip_reason
        rescue StandardError => e
          ::Rails.logger.warn("Failed to read skip_reason for #{record.span_id}: #{e.message}")
          nil
        end

        def paginated?
          @paginated_spans.respond_to?(:total_pages) && @paginated_spans.total_pages > 1
        end

        def pagination
          div(class: "raaf-card-footer") do
            render Molecules::Pagination.new(
              page: @paginated_spans.current_page,
              total_pages: @paginated_spans.total_pages,
              total_count: @paginated_spans.total_count,
              per_page: @paginated_spans.limit_value,
              href: ->(page) { tracing_spans_path(@params.merge(page: page)) }
            )
          end
        end

        def empty_state
          render(Organisms::Card.new) do
            render(Molecules::EmptyState.new(
                     icon: "layers", title: "No spans found",
                     text: "No spans in the selected range match your filters."
                   )) do
              render Atoms::Button.new(label: "Clear filters", variant: :secondary,
                                       href: tracing_spans_path)
            end
          end
        end
      end
    end
  end
end
