# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # The Tools screen: the registry of callable tools.
      #
      # The design's Tools screen is a registry — one card per tool, not one
      # row per call — because the question it answers is "which tool is
      # costing us" rather than "what happened at 09:41". A card leads to its
      # own calls on the Spans screen, which is built for listing them.
      #
      # Each card answers that question in money as well as in activity:
      # calls, error rate and p95, then spend and tokens.
      #
      # A "tool" here is whatever the agents called out to, which is wider
      # than the tools an LLM invoked by name: see +SpanRecord::TOOL_KINDS+.
      # Cards are grouped by the name a reader would use for the thing —
      # the function name for an LLM tool call, the class for everything
      # else.
      #
      class ToolSpans < BaseComponent
        # Tools whose name gives away what they do to the world. Read-only
        # tools are neutral; the ones that write are worth marking.
        WRITE_HINTS = %w[upsert create write insert update delete send post put].freeze
        GUARD_HINTS = %w[guard scrub redact pii compliance].freeze

        def initialize(total_tool_spans:, params: {})
          @total_tool_spans = total_tool_spans
          @params = params
        end

        def view_template
          # The design's Tools screen is the card grid and nothing else. The
          # "Recent calls" table that used to follow it answered a question
          # Spans?kind=tool already answers, on a screen built for listing.
          div(class: "raaf-page") do
            registry
          end
        end

        private

        def registry
          render Organisms::ToolRegistry.new(
            tools: aggregates.map { |name, agg| card_for(name, agg) },
            empty: { icon: "tools", title: "No tool calls recorded",
                     text: "No tool, custom or component spans in the selected range " \
                           "match the filters." }
          )
        end

        # ── Aggregation ───────────────────────────────────────────────────
        #
        # The registry is built from the whole filtered set rather than the
        # current page: a p95 taken from fifty rows of a thousand would be a
        # different number every time the page turned.

        def aggregates
          @aggregates ||= (grouped_in_sql || grouped_in_ruby).sort_by { |_name, agg| -agg[:calls] }
        end

        # Counting in the database rather than over loaded rows. The screen
        # asks one question per tool — how many, how many failed, how slow at
        # p95 — and a relation can answer all three without the page holding a
        # month of calls in memory. It used to load the rows and cap them at a
        # few thousand, which quietly turned every card into a sample: the
        # count on a card and the list it linked to disagreed.
        def grouped_in_sql
          return nil unless @total_tool_spans.respond_to?(:group)

          name = Arel.sql(name_sql)
          @total_tool_spans.except(:includes).reorder(nil).group(name).pluck(
            name,
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(*) FILTER (WHERE status = 'error')"),
            Arel.sql("PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY duration_ms)")
          ).to_h do |tool, calls, errors, p95|
            [tool, { calls: calls, errors: errors,
                     error_rate: (errors.to_f / calls) * 100, p95: p95 }]
          end
        end

        # The name a reader would use for the thing that was called, in SQL.
        # Each kind keeps it somewhere else, and the last branch unwraps the
        # tracer's `run.workflow.<kind>.<Class>.<method>` framing — the same
        # order {#tool_name} applies in Ruby, so a card and the calls behind
        # it are named alike.
        def name_sql
          <<~SQL.squish
            COALESCE(
              span_attributes::jsonb->'function'->>'name',
              span_attributes::jsonb->>'tool_name',
              span_attributes::jsonb->'tool'->>'name',
              span_attributes::jsonb->'custom'->>'name',
              #{SpanRecord::READABLE_NAME_SQL}
            )
          SQL
        end

        # The same summary for a plain array of spans, which is what a spec
        # and a caller holding records rather than a relation pass.
        def grouped_in_ruby
          Array(@total_tool_spans).group_by { |span| tool_name(span) }
                                  .transform_values { |spans| summarise(spans) }
        end

        def summarise(spans)
          durations = spans.filter_map(&:duration_ms).sort
          errors = spans.count(&:error?)

          { calls: spans.size,
            errors: errors,
            error_rate: (errors.to_f / spans.size) * 100,
            p95: percentile(durations, 0.95) }
        end

        def percentile(sorted, fraction)
          return nil if sorted.empty?

          sorted[[(sorted.length * fraction).ceil - 1, 0].max]
        end

        # What each tool was billed, and the tokens behind it.
        #
        # In Ruby rather than in the GROUP BY above, because a span's cost is
        # a Ruby question: SpanUsage prices tokens against the model that
        # produced them, and a search tool is billed a flat fee per call
        # instead. Only the spans that recorded usage are loaded, which on a
        # tool set is a small fraction of the calls.
        def billing
          @billing ||= billable_tool_spans
                       .group_by { |span| tool_name(span) }
                       .transform_values do |spans|
                         { cost: spans.sum(0.0) { |span| span.cost_usd.to_f },
                           tokens: spans.sum { |span| span.total_token_count.to_i } }
                       end
        end

        def billable_tool_spans
          scope = @total_tool_spans
          return Array(scope).select(&:billable?) unless scope.respond_to?(:with_billable_usage)

          scope.except(:includes).reorder(nil).with_billable_usage.to_a.select(&:billable?)
        end

        def card_for(name, agg)
          rate = agg[:error_rate]
          billed = billing[name]

          { name: name,
            icon: icon_for(name),
            tag: tag_for(name),
            tone: tone_for_tag(tag_for(name)),
            description: description_for(agg),
            calls: humanise(agg[:calls]),
            error_rate: "#{'%.1f' % rate}%",
            error_tone: if rate >= 5
                          :bad
                        else
                          (rate >= 1 ? :warn : :ok)
                        end,
            p95: duration(agg[:p95]),
            spend: spend_figure(billed),
            tokens: token_figure(billed),
            href: calls_path(name) }
        end

        # A tool nothing ever billed has no spend to report, and $0.00 reads
        # as a tool that is free rather than as one that was never measured.
        def spend_figure(billed)
          return nil if billed.nil?

          "$#{'%.2f' % billed[:cost]}"
        end

        def token_figure(billed)
          return nil if billed.nil? || billed[:tokens].zero?

          humanise(billed[:tokens])
        end

        # A card leads to its own calls, on the Spans screen. It used to lead
        # back to this one filtered to the tool, which — since the calls table
        # moved off this screen — showed the reader the same card again.
        #
        # The topbar's range is carried, so the calls you land on are the ones
        # the card counted.
        def calls_path(name)
          tracing_spans_path({ search: name, range: @params[:range] }
                               .compact.reject { |_, value| value.to_s.empty? })
        end

        def description_for(agg)
          return "#{agg[:errors]} of #{agg[:calls]} calls failed." if agg[:errors].positive?

          "#{humanise(agg[:calls])} calls, none failed."
        end

        def tag_for(name)
          key = name.to_s.downcase
          return "guard" if GUARD_HINTS.any? { |hint| key.include?(hint) }
          return "write" if WRITE_HINTS.any? { |hint| key.include?(hint) }

          "read"
        end

        def tone_for_tag(tag)
          { "write" => :warn, "guard" => :info }.fetch(tag, :neutral)
        end

        def icon_for(name)
          key = name.to_s.downcase
          return "shield-check" if tag_for(name) == "guard"
          return "database-add" if key.include?("upsert") || key.include?("crm")
          return "globe2" if key.include?("search") || key.include?("http")
          return "envelope-paper" if key.include?("mail") || key.include?("email")

          "wrench-adjustable"
        end

        # ── Formatting ────────────────────────────────────────────────────

        # `display_name` already knows where each kind hides its real name and
        # strips the `run.workflow.custom.` prefixes off the ones that don't,
        # so the registry groups on what a person would call the tool.
        def tool_name(span)
          attrs = span.span_attributes || {}

          attrs.dig("function", "name") || attrs["tool_name"] || attrs.dig("tool", "name") ||
            attrs.dig("custom", "name") || span.display_name
        end

        def duration(milliseconds)
          return "—" unless milliseconds

          milliseconds < 1000 ? "#{milliseconds.round}ms" : "#{'%.1f' % (milliseconds / 1000.0)}s"
        end

        def humanise(count)
          count >= 1000 ? "#{(count / 1000.0).round(1)}k" : count.to_s
        end
      end
    end
  end
end
