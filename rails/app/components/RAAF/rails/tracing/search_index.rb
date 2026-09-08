# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # The Search screen: one query bar, faceted counts, and one list of hits.
      #
      # Traces and spans arrive as separate result sets but are shown as a
      # single ranked list, because when you are chasing a string you do not
      # yet know which of the two holds it. The kind chip on each hit says
      # which it turned out to be.
      #
      class SearchIndex < BaseComponent
        EXAMPLES = [
          "crm_upsert",
          "execution expired",
          "Company::EnrichAgent",
          "error"
        ].freeze

        # @param query [String, nil]
        # @param results [Hash, nil] :traces, :spans, :total_traces, :total_spans
        # @param facets [Hash, nil] :kind and :status counts over the whole match
        # @param elapsed_ms [Integer, nil] how long the search itself took
        def initialize(query:, results: nil, facets: nil, elapsed_ms: nil, params: {})
          @query = query
          @results = results || {}
          @facets = facets || {}
          @elapsed_ms = elapsed_ms
          @params = params
        end

        def view_template
          div(class: "raaf-page") do
            render Organisms::SearchWorkbench.new(
              query: @query,
              action: tracing_search_path,
              meta: meta,
              examples: EXAMPLES,
              facets: facets,
              results: hits,
              empty: empty_state
            )
          end
        end

        private

        # "148 hits · 240ms", as the design writes it — the count answers
        # whether the query was specific enough, the timing whether it is one
        # you can keep refining.
        def meta
          return nil if @query.blank?

          [pluralize(total, "hit"), @elapsed_ms && "#{@elapsed_ms}ms"].compact.join(" · ")
        end

        def total
          @results[:total_traces].to_i + @results[:total_spans].to_i
        end

        def empty_state
          if @query.blank?
            { icon: "search", title: "Search the trace store",
              text: "Enter an id, a workflow, a tool name or any text from a span's attributes." }
          else
            { icon: "search", title: "No matches",
              text: "Nothing in the trace store matches #{@query.inspect}." }
          end
        end

        # ── Facets ────────────────────────────────────────────────────────
        #
        # The counts come from the controller, over the whole match rather
        # than the page, so a facet is a fact about the result set and not
        # about how far you have scrolled.

        def facets
          return [] if @query.blank?

          [facet("Kind", :kind), facet("Status", :status), facet("Workflow", :workflow)].compact
        end

        def facet(label, key)
          counts = @facets[key]
          return nil if counts.blank?

          { label: label,
            values: counts.sort_by { |_value, count| -count }.map do |value, count|
              active = @params[key.to_s] == value
              { label: value, count: count, active: active, href: facet_href(key, active ? nil : value) }
            end }
        end

        # A facet draws as a checkbox, so the checked one has to come off the
        # same way it went on: its link clears the filter rather than setting
        # it again. Paging resets either way, since page three of the old
        # result set means nothing in the new one.
        def facet_href(key, value)
          filters = @params.to_h.except(:traces_page, :spans_page).merge(q: @query)
          filters = value.nil? ? filters.except(key) : filters.merge(key => value)
          tracing_search_path(filters)
        end

        # ── Hits ──────────────────────────────────────────────────────────

        def hits
          return [] if @query.blank?

          Array(@results[:traces]).map { |trace| trace_hit(trace) } +
            Array(@results[:spans]).map { |span| span_hit(span) }
        end

        def trace_hit(trace)
          { kind: "pipeline",
            name: trace.workflow_name.presence || "Unnamed workflow",
            meta: "#{truncate_id(trace.trace_id)} · #{ago(trace.started_at)}",
            tone: tone_for(trace.status),
            snippet: "#{pluralize(trace.spans.size, 'span')} · #{duration(trace.duration_ms)} · #{trace.status}",
            href: tracing_trace_path(trace.trace_id) }
        end

        def span_hit(span)
          { kind: span.kind,
            name: span.display_name,
            meta: "#{truncate_id(span.trace_id)} · #{ago(span.start_time)}",
            tone: tone_for(span.status),
            snippet: snippet_for(span),
            href: trace_span_path(span.span_id, span.trace_id) }
        end

        # An error is what you were most likely looking for; failing that, the
        # attribute that actually contains the query.
        def snippet_for(span)
          details = span.error_details
          if details.present?
            return [details[:exception_type], details[:exception_message]].compact.join(" — ").presence ||
                   details[:status_description].to_s
          end

          matching_attribute(span) || "#{span.kind} · #{duration(span.duration_ms)} · #{span.status}"
        end

        def matching_attribute(span)
          return nil if @query.blank?

          needle = @query.downcase
          pair = (span.span_attributes || {}).find do |key, value|
            "#{key} #{value}".downcase.include?(needle)
          end
          return nil unless pair

          "#{pair[0]}: #{truncate(pair[1].to_s, length: 160)}"
        end

        def tone_for(status)
          case status.to_s
          when "error" then :bad
          when "cancelled", "skipped" then :warn
          else :ok
          end
        end

        def duration(milliseconds)
          return "—" unless milliseconds

          milliseconds < 1000 ? "#{milliseconds.round}ms" : "#{'%.1f' % (milliseconds / 1000.0)}s"
        end

        def ago(time)
          time_ago(time)
        end
      end
    end
  end
end
