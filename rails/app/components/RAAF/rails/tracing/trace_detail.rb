# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # A trace: the span waterfall, and the inspector for the span you picked.
      #
      # The waterfall answers when each span ran and how long it held the
      # trace open; the inspector answers what that span actually did. Both
      # the selected span and the inspector's tab are URL parameters, so a
      # link to a trace can land on the span and the tab that explain it —
      # which is the whole point of sending someone a trace.
      #
      class TraceDetail < BaseComponent
        include PayloadTabs
        include SpanAccounting

        def initialize(trace:, params: {})
          @trace = trace
          @params = params
        end

        def view_template
          div(class: "raaf-page") do
            summary_bar
            div(class: "raaf-trace-split") do
              waterfall
              aside
            end
          end
        end

        private

        # The bar carries the id, the status and the stats, which is how the
        # design identifies a trace; the workflow name is the page title. It
        # holds no actions — the sidebar goes back to Traces, and the JSON is
        # at this path with `.json` on the end.
        def summary_bar
          div(class: "raaf-trace-bar") do
            render Atoms::Mono.new(@trace.trace_id)
            render Atoms::StatusBadge.new(@trace.status)
            div(class: "raaf-trace-bar-stats") do
              summary_stats.each { |stat| summary_stat(stat) }
            end
          end
        end

        def summary_stat(stat)
          span(class: "raaf-trace-stat") do
            render Atoms::Icon.new(stat[:icon])
            plain stat[:label]
            render Atoms::Mono.new(stat[:value])
          end
        end

        # The token stat is dropped from a trace that consumed none rather
        # than printed as a zero: a run made entirely of search calls was
        # never measured in tokens, and saying "tokens 0" beside its bill
        # reads as a run that cost nothing.
        def summary_stats
          stats = [started_stat,
                   { icon: "layers", label: "spans", value: spans.size.to_s },
                   { icon: "clock", label: "duration", value: duration(@trace.duration_ms || window) }].compact
          stats << { icon: "coin", label: "tokens", value: format_tokens(total_tokens) } if total_tokens.positive?
          stats << { icon: "cash", label: "cost", value: format_money(total_cost) }
          stats
        end

        # When the trace ran, in absolute time.
        #
        # Every other time on this page is relative to the trace: the
        # waterfall is offsets from its origin and the rows read "4 minutes
        # ago". None of that lines a trace up against an application log, an
        # incident window or a deploy, which is the usual reason for opening
        # one. The Replay screen already prints this format.
        def started_stat
          return nil unless @trace.started_at

          { icon: "calendar-event", label: "started",
            value: @trace.started_at.strftime("%Y-%m-%d %H:%M:%S") }
        end

        # ── Waterfall ─────────────────────────────────────────────────────

        def waterfall
          render(Organisms::Card.new(title: "Span waterfall",
                                     subtitle: "0 → #{duration(window)}", flush: true)) do
            render Organisms::SpanWaterfall.new(
              spans: waterfall_rows,
              total_ms: window,
              selected: selected&.span_id
            )
          end
        end

        def waterfall_rows
          depths = depth_map

          spans.map do |span|
            { id: span.span_id,
              kind: span.kind,
              name: span.display_name,
              duration: duration(span.duration_ms),
              tokens: span_tokens(span),
              start_ms: offset_ms(span),
              duration_ms: span.duration_ms.to_f,
              level: depths[span.span_id].to_i,
              tone: span_tone(span),
              href: tracing_trace_path(@trace.trace_id) +
                "?#{{ span: span.span_id, tab: tab }.to_query}" }
          end
        end

        # ── Inspector ─────────────────────────────────────────────────────

        # The inspector reads what the span recorded; the panel under it is
        # what can be done to the span. They share the column so that the
        # waterfall keeps its width, and because a policy is worth seeing only
        # once a span is picked.
        def aside
          div(class: "raaf-trace-aside") do
            inspector
            span_policies
          end
        end

        # Absent unless this span is one a policy could grade — the panel
        # decides that for itself, since the rule is the pipeline's, not this
        # page's.
        def span_policies
          return if selected.nil?

          render RAAF::Rails::Continuous::SpanPoliciesPanel.new(span: selected)
        end

        def inspector
          if selected.nil?
            render Molecules::EmptyState.new(icon: "hand-index", title: "Pick a span",
                                             text: "Choose a row in the waterfall to inspect it.")
            return
          end

          render Organisms::SpanInspector.new(
            kind: selected.kind,
            name: selected.display_name,
            tab: tab,
            tabs: inspector_tabs,
            meta: inspector_meta,
            messages: payload_messages,
            error: inspector_error,
            tokens: token_rows,
            raw: raw_record,
            actions: span_replay_actions(selected)
          )
        end

        def inspector_tabs
          tab_definitions.map do |item|
            { id: item[:id], label: item[:label],
              href: tracing_trace_path(@trace.trace_id) +
                "?#{{ span: selected.span_id, tab: item[:id] }.to_query}" }
          end
        end

        # One tab per payload section this span recorded, then the rest — of
        # which the accounting tab is offered only to a span that has
        # something to account for, and the error tab only to one that failed.
        def tab_definitions
          @tab_definitions ||= payload_tab_definitions(payload_messages,
                                                       accounting: accounting_label(selected),
                                                       error: failed?)
        end

        def inspector_meta
          attrs = selected.span_attributes || {}
          model = attrs["model"] || attrs.dig("llm", "model")

          [duration(selected.duration_ms),
           model.presence || "#{selected.kind} span",
           accounting_meta(selected),
           { value: selected.status, tone: selected.error? ? :bad : :ok }].compact
        end

        # A span can report a failure without recording an exception — the
        # tracer only captures one if the processor emitted an `exception`
        # event. Saying "no error" on a span whose status is `error` would
        # contradict the badge two lines above it.
        # What earns the span an Error tab, and makes the inspector open on
        # it. Cancellation counts: the span did not finish, and the reader
        # opened it to find out why.
        def failed?
          selected.present? && (selected.error? || selected.cancelled?)
        end

        def inspector_error
          return nil unless failed?

          details = selected.error_details || {}

          { klass: details[:exception_type].presence || fallback_class,
            message: details[:exception_message].presence ||
              details[:status_description].presence ||
              selected.skip_reason.presence || fallback_message,
            backtrace: details[:exception_stacktrace] }
        end

        def fallback_class
          selected.cancelled? ? "Cancelled" : "Error"
        end

        def fallback_message
          "The span reported #{selected.status}, but no exception was recorded on it."
        end

        def payload_messages
          @payload_messages ||= payload_messages_from(selected.span_attributes)
        end

        # The span's own accounting, in whatever unit it is billed in, and
        # then the trace's running totals — which are the reason to read a
        # span's cost here rather than on its own page.
        def token_rows
          accounting_rows(selected, extra: trace_total_rows)
        end

        # The trace's running totals, under the span's own. Tokens are named
        # only when the span beside them is billed in tokens and the trace
        # actually consumed some — a trace of nothing but search calls has no
        # token count to report, and "0" over a bill of $0.003 contradicts it.
        def trace_total_rows
          rows = []
          rows << { label: "Trace tokens", value: format_tokens(total_tokens), tone: :muted } if trace_tokens?
          rows << { label: "Trace cost", value: format_money(total_cost), tone: :ok }
          rows
        end

        def trace_tokens?
          billed_in_tokens?(selected) && total_tokens.positive?
        end

        def raw_record
          { span_id: selected.span_id,
            trace_id: selected.trace_id,
            parent_id: selected.parent_id,
            name: selected.name,
            kind: selected.kind,
            status: selected.status,
            start_time: selected.start_time,
            duration_ms: selected.duration_ms,
            attributes: selected.span_attributes,
            events: selected.events }
        end

        # ── Selection ─────────────────────────────────────────────────────

        # Without an explicit choice the inspector opens on whatever failed —
        # that is what you came to look at — and on the root span otherwise.
        def selected
          return @selected if defined?(@selected)

          @selected = spans.find { |span| span.span_id == @params[:span] } ||
                      spans.find(&:error?) ||
                      spans.first
        end

        def tab
          @tab ||= resolve_tab(@params[:tab], tab_definitions, failed: failed?)
        end

        # ── Spans and timings ─────────────────────────────────────────────

        def spans
          @spans ||= @trace.spans.includes(:children).order(start_time: :asc).to_a
        end

        def origin
          @origin ||= spans.filter_map(&:start_time).min
        end

        def offset_ms(span)
          return 0.0 if origin.nil? || span.start_time.nil?

          (span.start_time - origin) * 1000.0
        end

        # The trace's own window, so every bar is measured against the same
        # clock even when a child outlives its recorded parent.
        def window
          @window ||= spans.map { |span| offset_ms(span) + span.duration_ms.to_f }.max.to_f
        end

        def depth_map
          @depth_map ||= begin
            by_id = spans.index_by(&:span_id)

            spans.each_with_object({}) do |span, depths|
              depth = 0
              cursor = span
              while cursor&.parent_id && (parent = by_id[cursor.parent_id]) && depth < 32
                depth += 1
                cursor = parent
              end
              depths[span.span_id] = depth
            end
          end
        end

        def span_tone(span)
          return :bad if span.error?
          return :idle if span.cancelled?

          :ok
        end

        # ── Tokens and cost ───────────────────────────────────────────────

        def span_token_count(span)
          RAAF::Tracing::SpanUsage.total_tokens(usage_for(span))
        end

        def total_tokens
          @total_tokens ||= spans.sum { |span| span_token_count(span).to_i }
        end

        def total_cost
          @total_cost ||= spans.filter_map { |span| span_cost(span) }
                               .then { |costs| costs.empty? ? nil : costs.sum }
        end

        # What one span put on the trace's bill, in the unit it is billed in.
        # This total used to know only how to price tokens, so a trace whose
        # spend was mostly search fees reported the fraction of itself that
        # happened to have run through a model.
        def span_cost(span)
          case accounting_mode(span)
          when :cost then call_cost(span)
          when :tokens then RAAF::Tracing::SpanUsage.cost(usage_for(span))
          end
        end

        def span_tokens(span)
          count = span_token_count(span)

          count.to_i.positive? ? format_tokens(count) : nil
        end

        # ── Formatting ────────────────────────────────────────────────────

        def duration(milliseconds)
          return "—" unless milliseconds

          milliseconds < 1000 ? "#{milliseconds.round}ms" : "#{'%.1f' % (milliseconds / 1000.0)}s"
        end
      end
    end
  end
end
