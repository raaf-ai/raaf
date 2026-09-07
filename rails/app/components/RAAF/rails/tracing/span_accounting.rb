# frozen_string_literal: true

require "raaf/tracing/span_usage"

module RAAF
  module Rails
    module Tracing
      ##
      # What a span cost, in the unit that span is actually billed in.
      #
      # One "Tokens & cost" panel printed over every kind of span said the
      # wrong thing twice. A search span is charged a flat fee per query and
      # reports no tokens, so the panel showed it as `0 / 0 / 0` — which reads
      # as "this was free" over a call the provider invoiced. And a job span
      # buys nothing at all: it is a bracket around the work its children did,
      # so the same three zeros were not an understatement there but a
      # question nobody had asked.
      #
      # So a span says how it is billed, and the inspector asks before it
      # decides what to show:
      #
      # - +:tokens+ — priced per token by a model. Input, output, the tokens a
      #   provider billed without itemising, and what each of those cost.
      # - +:cost+ — priced per call. Search providers charge for the query, so
      #   the token half of the panel is not zero here, it is not a quantity
      #   this span has.
      # - +:none+ — not billed. A job's spend is the sum of its children, and
      #   each child already reports its own on its own page.
      #
      # The rule itself lives in +RAAF::Tracing::SpanUsage+, beside the usage
      # shapes it reads; this module is only how the two inspectors present it.
      # Keeping it there is what stops a search costing one thing on a trace
      # screen and nothing at all in the Cost & usage rollups.
      #
      module SpanAccounting
        private

        # How this span is billed. The rule lives in the tracing gem, beside
        # the usage shapes, so the screens and the rollups behind Cost & usage
        # cannot decide differently what a search costs.
        #
        # @param span [#kind, #span_attributes] Span or span record
        # @return [Symbol] +:tokens+, +:cost+ or +:none+
        def accounting_mode(span)
          RAAF::Tracing::SpanUsage.billing_mode(span)
        end

        # The accounting panel's rows, in this span's own unit.
        #
        # Empty when the span is unbilled, or when it is priced per token and
        # recorded none — the inspector answers that with an empty state
        # rather than a column of zeros.
        #
        # @param span [#kind, #span_attributes] Span or span record
        # @param extra [Array<Hash>] rows to append, for a caller with context
        #   of its own to add (the trace screen's running totals)
        # @return [Array<Hash>] :label, :value, and optionally :tone
        def accounting_rows(span, extra: [])
          rows = case accounting_mode(span)
                 when :cost then call_cost_rows(span)
                 when :tokens then token_cost_rows(span)
                 else []
                 end

          rows.empty? ? rows : rows + extra
        end

        # What the panel is called for this span, or nil when it has none.
        #
        # @param span [#kind, #span_attributes] Span or span record
        # @return [String, nil]
        def accounting_label(span)
          case accounting_mode(span)
          when :cost then "Cost"
          when :tokens then "Tokens & cost"
          end
        end

        # The one figure this span contributes to a summary bar, or nil when
        # it contributes none. A search span's headline is its charge; a
        # token-priced span's is its token count.
        #
        # @param span [#kind, #span_attributes] Span or span record
        # @return [Hash, nil] :icon, :label, :value
        def accounting_stat(span)
          case accounting_mode(span)
          when :cost
            { icon: "cash", label: "cost", value: format_money(call_cost(span)) }
          when :tokens
            { icon: "coin", label: "tokens",
              value: format_tokens(RAAF::Tracing::SpanUsage.total_tokens(usage_for(span))) }
          end
        end

        # Whether a figure counted in tokens belongs beside this span at all.
        #
        # Asked by a caller with its own totals to add: a "Trace tokens" line
        # under a search span's charge is the token accounting the cost-only
        # panel exists to keep out, and it reads as zero besides.
        #
        # @param span [#kind, #span_attributes] Span or span record
        # @return [Boolean]
        def billed_in_tokens?(span)
          RAAF::Tracing::SpanUsage.billed_in_tokens?(span)
        end

        # The same figure as one line of the inspector's header strip.
        #
        # @param span [#kind, #span_attributes] Span or span record
        # @return [String, nil]
        def accounting_meta(span)
          stat = accounting_stat(span)
          return nil unless stat

          "#{stat[:value]} #{stat[:label]}"
        end

        # ── Per-token spans ───────────────────────────────────────────────

        def token_cost_rows(span)
          usage = usage_for(span)
          return [] unless RAAF::Tracing::SpanUsage.total_tokens(usage)

          model_row(usage) + token_rows_for(usage) + cost_rows_for(usage)
        end

        def model_row(usage)
          usage[:model] ? [{ label: "Model", value: usage[:model], tone: :muted }] : []
        end

        def token_rows_for(usage)
          rows = [{ label: "Input tokens", value: format_tokens(usage[:input]) },
                  { label: "Output tokens", value: format_tokens(usage[:output]) }]

          # Only worth a row when the provider actually charged for tokens it
          # did not itemise — Gemini's thinking tokens show up only as the gap
          # between the reported total and input + output.
          thinking = unitemised_output(usage)
          rows << { label: "Thinking tokens", value: format_tokens(thinking) } if thinking

          rows << { label: "Total tokens",
                    value: format_tokens(RAAF::Tracing::SpanUsage.total_tokens(usage)) }
          rows
        end

        # Cost split the way it is billed, or one honest dash.
        #
        # A model with no pricing entry has an unknown cost, not a zero one,
        # and three rows of "—" would only say that three times.
        def cost_rows_for(usage)
          breakdown = RAAF::Tracing::SpanUsage.cost_breakdown(usage)
          return [{ label: "Cost", value: "—", tone: :muted }] unless breakdown

          [{ label: "Input cost", value: format_money(breakdown[:input_cost]) },
           { label: "Output cost", value: format_money(breakdown[:output_cost]) },
           { label: "Total cost", value: format_money(breakdown[:total_cost]), tone: :ok }]
        end

        # Tokens the provider billed for but did not itemise, or nil when it
        # itemised everything it charged for.
        def unitemised_output(usage)
          gap = RAAF::Tracing::SpanUsage.billable_output(usage) - usage[:output].to_i

          gap.positive? ? gap : nil
        end

        # ── Per-call spans ────────────────────────────────────────────────

        def call_cost_rows(span)
          provider = provider_name(span)
          rows = provider ? [{ label: "Provider", value: provider, tone: :muted }] : []

          rows + [{ label: "Cost", value: format_money(call_cost(span)), tone: :ok }]
        end

        # What one call cost, in dollars: the flat fee the component recorded,
        # or the token cost for a provider that answers with a model rather
        # than a price list. Nil when neither is known.
        def call_cost(span)
          RAAF::Tracing::SpanUsage.spend_for_span(span)
        end

        def provider_name(span)
          RAAF::Tracing::SpanUsage.provider_for_span(span)
        end

        # ── Reading the span ──────────────────────────────────────────────

        # Memoised per span: an inspector asks for the same span's usage
        # several times over while building one panel.
        def usage_for(span)
          @span_accounting_usage ||= {}
          @span_accounting_usage[span.span_id] ||= RAAF::Tracing::SpanUsage.for_span(span)
        end

        # ── Formatting ────────────────────────────────────────────────────

        def format_tokens(count)
          value = count.to_i
          return "0" if value.zero?

          value >= 1000 ? "#{(value / 1000.0).round(1)}k" : value.to_s
        end

        # Nil is not zero: a span whose price nobody knows has an unknown
        # cost, and printing $0.000 for it understates the bill.
        def format_money(amount)
          amount ? "$#{'%.3f' % amount.to_f}" : "—"
        end
      end
    end
  end
end
