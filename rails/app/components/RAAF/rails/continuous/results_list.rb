# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # Every verdict continuous evaluation has recorded, from the Results
      # screen in RAAF Continuous.dc.html: three panels describing the
      # population, the filter strip, and the table itself.
      #
      # Two departures from the canvas, both because of what is stored:
      #
      # - **The histogram is coloured by score, not by height.** The canvas
      #   tints a bucket by how tall it is, which reads correctly only while
      #   the tall buckets happen to be the high-scoring ones. Colouring each
      #   bucket by the score it stands for keeps the reading true when a
      #   policy starts failing and the pile moves left.
      # - **No composite.** A result here is one evaluator against one field,
      #   so the Score column is that evaluator's own number. Nothing combines
      #   them into the per-span composite the canvas's Score column implies.
      #
      class ResultsList < RAAF::Rails::Tracing::BaseComponent
        # Columns and fr weights taken from RAAF Continuous.dc.html.
        COLUMNS = [
          { label: "Span", span: 1.5 },
          { label: "Policy", span: 1.4 },
          { label: "Evaluator", span: 1.2 },
          { label: "Method", span: 0.8 },
          { label: "Score", span: 0.7, align: :right },
          { label: "Verdict", span: 0.8, align: :right },
          { label: "When", span: 0.8, align: :right }
        ].freeze

        STATUSES = [
          { label: "All", value: nil },
          { label: "Good", value: "good" },
          { label: "Average", value: "average" },
          { label: "Bad", value: "bad" },
          { label: "Error", value: "error" }
        ].freeze

        # The verdict split, in the order the canvas stacks it: the outcome a
        # policy wants first, the one somebody has to act on last.
        VERDICTS = [
          { key: :good, label: "Good", tone: :ok },
          { key: :average, label: "Average", tone: :warn },
          { key: :bad, label: "Bad", tone: :bad },
          { key: :error, label: "Errored", tone: nil }
        ].freeze

        # Above this a score is healthy, below the lower bound it is failing.
        # The tiers the experiment screens use, so one score does not change
        # colour between pages.

        # @param agents [Array<String>] every agent that has produced a result,
        #   for the strip's filter
        # @param policies [Array<Array(String, Integer)>] `[name, id]` for every
        #   policy that has produced one, so a policy page can hand its reader
        #   the rows behind its own numbers
        # @param summary [Hash] counts per verdict, plus :total, :scored and
        #   :median, over the population the chips filter
        # @param distribution [Array<Hash>] one bucket per tenth, oldest first,
        #   each carrying :label, :low, :high and :count
        # @param worst_scorers [Array<Hash>] :name, :average, :count and a
        #   :delta that is nil where the preceding window measured nothing
        # @param scorer_window [String] the window those scorers cover, said
        #   out loud — "24h"
        def initialize(results:, page: 1, per_page: 50, filters: {}, agents: [], policies: [],
                       summary: {}, distribution: [], worst_scorers: [], scorer_window: "24h")
          @results = results
          @page = page
          @per_page = per_page
          @filters = filters || {}
          @agents = agents || []
          @policies = policies || []
          @summary = summary || {}
          @distribution = distribution || []
          @worst_scorers = worst_scorers || []
          @scorer_window = scorer_window
        end

        def view_template
          div(class: "raaf-page") do
            panels
            filters
            table
          end
        end

        private

        # ── Panels ────────────────────────────────────────────────────────

        def panels
          div(class: "raaf-results-panels") do
            distribution_panel
            verdict_panel
            worst_scorers_panel
          end
        end

        # ── Score distribution ────────────────────────────────────────────

        def distribution_panel
          render(Organisms::Card.new(title: "Score distribution",
                                     subtitle: distribution_summary)) do
            if scored_any?
              render Molecules::Sparkbars.new(
                values: @distribution.map { |bucket| bucket[:count] },
                tones: distribution_tones, tips: distribution_tips,
                label: "Scores by tenth", class: "raaf-histogram"
              )
              distribution_axis
            else
              render Molecules::EmptyState.new(
                icon: "bar-chart", title: "Nothing scored",
                text: "No result in this set carries a score."
              )
            end
          end
        end

        def distribution_axis
          div(class: "raaf-histogram-axis") do
            @distribution.each { |bucket| span { bucket[:label] } }
          end
        end

        # Every bucket is tinted by the score it stands for rather than by how
        # many landed in it — see the class note.
        def distribution_tones
          @distribution.each_with_index.to_h do |bucket, index|
            [index, score_tone(bucket[:low])]
          end
        end

        def distribution_tips
          @distribution.map do |bucket|
            "#{'%.1f' % bucket[:low]}–#{'%.1f' % bucket[:high]} · " \
              "#{counted(bucket[:count], 'result')}"
          end
        end

        def distribution_summary
          return "no scores recorded" unless scored_any?

          median = @summary[:median]
          [counted(@summary[:scored].to_i, "scored result"),
           median && "median #{score_text(median)}"].compact.join(" · ")
        end

        def scored_any?
          @summary[:scored].to_i.positive?
        end

        # ── Verdict split ─────────────────────────────────────────────────

        def verdict_panel
          render(Organisms::Card.new(title: "Verdict split",
                                     subtitle: counted(verdict_total, "result"))) do
            if verdict_total.zero?
              render Molecules::EmptyState.new(
                icon: "clipboard-check", title: "No verdicts",
                text: "Nothing has been graded in this set yet."
              )
            else
              VERDICTS.each { |verdict| verdict_row(verdict) }
            end
          end
        end

        def verdict_row(verdict)
          count = @summary[verdict[:key]].to_i
          share = count / verdict_total.to_f

          render Molecules::MeterRow.new(
            name: verdict[:label],
            value: "#{delimited(count)} · #{(share * 100).round(1)}%",
            pct: (share * 100).round,
            tone: verdict[:tone],
            tip: "#{counted(count, 'result')} of #{delimited(verdict_total)}"
          )
        end

        def verdict_total
          @verdict_total ||= VERDICTS.sum { |verdict| @summary[verdict[:key]].to_i }
        end

        # ── Worst evaluators ──────────────────────────────────────────────

        def worst_scorers_panel
          render(Organisms::Card.new(title: "Worst evaluators · #{@scorer_window}",
                                     subtitle: worst_scorers_summary)) do
            if @worst_scorers.empty?
              render Molecules::EmptyState.new(
                icon: "sliders", title: "Nothing graded",
                text: "No evaluator has produced a score in the last #{@scorer_window}."
              )
            else
              @worst_scorers.each { |scorer| worst_scorer_row(scorer) }
            end
          end
        end

        def worst_scorer_row(scorer)
          average = scorer[:average].to_f

          render Molecules::MeterRow.new(
            name: scorer[:name].to_s.tr("_", " "),
            value: score_text(average),
            pct: (average * 100).round,
            tone: score_tone(average),
            meta: delta_text(scorer[:delta]),
            inline: true,
            tip: worst_scorer_tip(scorer)
          )
        end

        # The delta is against the window immediately before this one, which
        # the row cannot say in the four characters it has for it.
        def worst_scorer_tip(scorer)
          ["mean #{score_text(scorer[:average])} over #{counted(scorer[:count].to_i, 'result')}",
           scorer[:delta] && "#{delta_text(scorer[:delta])} vs the preceding #{@scorer_window}"]
            .compact.join(" · ")
        end

        # Nothing to compare against is not the same as no change, so an
        # evaluator the preceding window never measured makes no claim at all.
        def delta_text(delta)
          return nil if delta.nil?
          return "flat" if delta.round(2).zero?

          "%+.2f" % delta
        end

        def worst_scorers_summary
          return "nothing graded in the window" if @worst_scorers.empty?

          "lowest mean first, against the preceding #{@scorer_window}"
        end

        # ── Filters ───────────────────────────────────────────────────────

        def filters
          render(Molecules::FilterBar.new(chips: status_chips, panel: true,
                                          lead: agent_filter)) do
            policy = policy_filter
            render policy if policy
            render Atoms::Mono.new(count_label, tone: :muted)
          end
        end

        def agent_filter
          Molecules::ScopeFilter.new(
            name: "agent", value: @filters[:agent], options: @agents,
            action: continuous_results_path, prefix: "agent",
            carry: { "status" => @filters[:status], "policy" => @filters[:policy] }
          )
        end

        # Absent when nothing has been graded yet: a filter whose only choice
        # is "all" asks a question with one answer.
        def policy_filter
          return if @policies.empty?

          Molecules::ScopeFilter.new(
            name: "policy", value: @filters[:policy], options: @policies,
            action: continuous_results_path, prefix: "policy", icon: "clipboard-check",
            carry: { "status" => @filters[:status], "agent" => @filters[:agent] }
          )
        end

        def status_chips
          STATUSES.map do |status|
            { label: status[:label],
              active: @filters[:status].presence == status[:value],
              href: filtered_path(status[:value]) }
          end
        end

        def filtered_path(status)
          carried = { agent: @filters[:agent], policy: @filters[:policy], status: status }
          continuous_results_path(carried.compact.reject { |_, v| v.to_s.empty? })
        end

        # The canvas prints "N of 18,204 scored spans" — the rows on screen
        # against the population the panels above describe. Says the one
        # figure when nothing narrowed the table, rather than "N of N".
        def count_label
          shown = total_count
          population = @summary[:total].to_i

          return counted(shown, "result") if population.zero? || population <= shown

          "#{delimited(shown)} of #{delimited(population)} results"
        end

        def total_count
          @results.respond_to?(:total_count) ? @results.total_count : @results.size
        end

        # ── Table ─────────────────────────────────────────────────────────

        def table
          render(Organisms::Card.new(flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "graph-up", title: "No results",
                              text: "Nothing matches the current filters." }
                   )) do |grid|
              @results.each { |result| row(grid, result) }
            end

            pagination if paginated?
          end
        end

        def row(grid, result)
          grid.row(href: continuous_result_path(result), cells: [
                     { value: Molecules::TitleMeta.new(truncate_id(result.span_id),
                                                       result.agent_name.presence || "unknown",
                                                       mono: true) },
                     { value: Atoms::Mono.new(policy_name(result)) },
                     { value: scorer_cell(result) },
                     { value: method_cell(result) },
                     { value: Atoms::Mono.new(score_text(result.score),
                                              tone: score_tone(result.score)), align: :right },
                     { value: Atoms::StatusBadge.new(result.status), align: :right },
                     { value: Atoms::Mono.new(time_ago(result.created_at), tone: :muted),
                       align: :right }
                   ])
        end

        # The scorer as its own class names it, where it names itself: the row
        # is read by somebody looking for a check, and `dmu_title_relevance` is
        # the spelling a policy is written in rather than the one a check is
        # known by. The field it graded stays the second line, which is what
        # distinguishes the several rows one evaluator wrote for one span.
        def scorer_cell(result)
          title = titles[result.evaluator_name].presence
          attrs = { title: check_description(result) }.compact

          Molecules::TitleMeta.new(title || result.evaluator_name.to_s.tr("_", " "),
                                   field_for(result), mono: title.blank?, **attrs)
        end

        def titles = @titles ||= EvaluatorTitles.new

        # What kind of scoring produced the figure beside it. The column reads
        # down as much as across: it is how somebody scanning a page of results
        # sees which of them cost a model call, and which would give the same
        # answer if they ran again.
        def method_cell(result)
          Atoms::Badge.for_check_type(RAAF::Rails::ScoringMethod.for_result(result), size: :sm) ||
            Atoms::Mono.new("—", tone: :muted)
        end

        # The link is optional and null for two reasons that look identical in
        # the row: a deleted policy nils it, and a result written outside a
        # policy (a smoke run whose evaluator resolves to no policy row) never
        # had one. The column says the link is absent rather than claiming a
        # deletion it cannot see, and rather than printing nothing and reading
        # as a missing value.
        def policy_name(result)
          result.evaluation_policy&.name.presence || "no policy"
        end

        # A result is about one field of one evaluator, and the field is what
        # distinguishes ten rows a policy wrote for the same span.
        #
        # The check's own name where the row recorded one: `confidence` is the
        # field an evaluator reads, and "Confidence In Range" is what it asks of
        # it, which is the difference between a column that identifies a row and
        # one that says what was measured.
        def field_for(result)
          declared_check(result)&.dig("display_name").presence || field_name_for(result)
        end

        def field_name_for(result)
          field = result.metadata&.dig("field_name").presence ||
                  result.metadata&.dig(:field_name).presence ||
                  result.details&.dig("field_name").presence
          field.to_s.tr("_", " ").presence || result.evaluator_type.to_s.tr("_", " ")
        end

        # The sentence the check was declared with, as the cell's hover text.
        # A row is one line; the sentence belongs on the result's own screen,
        # and this is the cheapest way to read it without going there.
        def check_description(result)
          declared_check(result)&.dig("description").presence
        end

        # Named only where the row recorded exactly one check. Several checks
        # on one field means the row cannot say which of them the figure came
        # from, and naming the wrong one is worse than naming none.
        def declared_check(result)
          stored = result.details&.dig("declared_checks")
          return nil unless stored.is_a?(Array) && stored.one?

          stored.first if stored.first.is_a?(Hash)
        end

        def paginated?
          @results.respond_to?(:total_pages) && @results.total_pages > 1
        end

        def pagination
          render Molecules::Pagination.new(
            page: @results.current_page, total_pages: @results.total_pages,
            total_count: @results.total_count, per_page: @per_page,
            href: ->(n) { continuous_results_path(@filters.to_h.merge(page: n).compact) }
          )
        end

        # ── Formatting ────────────────────────────────────────────────────
      end
    end
  end
end
