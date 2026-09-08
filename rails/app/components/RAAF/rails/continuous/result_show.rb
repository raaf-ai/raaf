# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # One graded verdict, from the Result screen in RAAF Continuous.dc.html:
      # a header carrying the span, the verdict and the score; the check
      # breakdown, the judge's reasoning and the payload that was scored down
      # the left; the evaluation's own metadata, its timeline and its
      # neighbours down the right.
      #
      # Three departures from the canvas, all of them data rather than layout:
      #
      # - **No threshold marker.** The canvas draws each check's bar against
      #   the threshold it had to clear, and prints the composite's threshold
      #   under it. No threshold is stored on a policy, an evaluator or a
      #   result, so a marker here would be a line drawn at a number nobody
      #   set.
      # - **No findings list.** The canvas itemises what an evaluator found — the
      #   entity, where in the output it sat, why it counted. An evaluator
      #   records a score and prose; the spans of text behind them are not
      #   kept, so the reasoning is the whole of what can be shown.
      # - **The payload is the span's, not a stored copy.** The canvas prints
      #   the input and output the evaluator saw. A result stores neither, so
      #   this reads them off the span it graded, and says so when the span
      #   has since been pruned.
      #
      # One addition the canvas does not draw: an LLM judge's own call. Where
      # a rule-based evaluator's verdict can be re-derived from the payload and
      # the rule, a judge's cannot be checked at all without reading what it
      # was asked and what it answered, so the exchange gets a section.
      #
      class ResultShow < RAAF::Rails::Tracing::BaseComponent
        # Above this a score is healthy, below the lower bound it is failing.
        # The tiers every other eval screen uses.

        # A rule-based reasoning line tags each clause with its verdict, and
        # is read back apart along those tags.
        VERDICT_TAG = /\A\[([A-Z][A-Z ]*)\]\s*/
        GOOD_TAGS = %w[GOOD PASS OK].freeze
        BAD_TAGS = %w[BAD FAIL ERROR].freeze

        # Measurements the screen already carries, or carries better: the
        # judge's exchange has its own section, and the prose is the card the
        # figures are listed under. `id_key` is not a measurement at all — it
        # tells a shared evaluator which attribute holds an item's identity, and
        # the identities it selects are already printed beside the items that
        # failed, so naming the attribute again pairs a label with no figure.
        #
        # A judge's own account of itself is skipped here for a different
        # reason: it is prose, and a key-value cell is 220px wide, monospaced
        # and clipped at 600 characters. Both are drawn as prose further down.
        MEASUREMENT_SKIP = %w[judge_prompt judge_response judge_model judge_fallback
                              reasoning message id_key
                              chain_of_thought criteria_evaluation criteria_count].freeze

        # Key endings that name a unit rather than a quantity.
        UNIT_SUFFIXES = %w[_ms _usd _tokens].freeze

        # What a span collector writes where it found nothing. Printed as a
        # payload they read as the agent's own words.
        PAYLOAD_PLACEHOLDERS = ["[]", "{}", "No content", "No result available",
                                "No user message found", "No agent response found",
                                "No system instructions"].freeze

        # @param span [RAAF::Rails::Tracing::SpanRecord, nil] the span that was
        #   graded, when it is still on record
        # @param sibling_results [Enumerable] the other results for this span
        # @param payload_tab [String, nil] "input" or "output", which half of
        #   the scored payload to show
        # @param history [CheckHistory, nil] what this check has scored on
        #   other spans, which is what makes one verdict readable
        def initialize(result:, span: nil, sibling_results: [],
                       payload_tab: nil, history: nil)
          @result = result
          @span = span
          @sibling_results = sibling_results
          @payload_tab = payload_tab
          @history = history
          load_evaluator_metadata
        end

        def view_template
          div(class: "raaf-page") do
            breadcrumb
            header
            div(class: "raaf-detail-split") do
              div(class: "raaf-stack") { main_column }
              div(class: "raaf-stack") { side_column }
            end
          end
        end

        private

        def main_column
          scorer_breakdown
          evaluation_details
          reasoning
          judge_call
          payload
          sibling_results
        end

        def side_column
          metadata
          timeline
          check_history
        end

        # ── Header ────────────────────────────────────────────────────────

        def breadcrumb
          render Molecules::Breadcrumb.new(items: [
                                             { label: "Results", href: continuous_results_path },
                                             { label: "##{@result.id}" }
                                           ])
        end

        def header
          render(Organisms::RecordHead.new(
                   title: @result.span_id.to_s, mono: true,
                   description: check_summary,
                   status: @result.status,
                   badges: [method_badge].compact,
                   meta: head_meta,
                   stats: head_stats
                 )) { links }
        end

        # What this check is for, not what it decided this time.
        #
        # The canvas leads with a summary written for the run and keeps the
        # judge's reasoning in its own section below. Only one piece of prose
        # is stored per result, and it is the reasoning — which runs to
        # paragraphs and belongs in a section rather than in a header. So the
        # header carries the check's own description, which is short and says
        # what was being asked, and the reasoning keeps its section.
        #
        # Not `summary`: every HTML element is a method on a Phlex component,
        # so a helper by that name silently takes over `<summary>` and any
        # disclosure written further down the class renders as an empty tag.
        def check_summary
          check_description(field_name).presence || @evaluator_description.presence
        end

        # The model only where the evaluation involved one. A rule-based
        # verdict names no model anywhere else on the screen, and printing the
        # graded agent's here would make the strip the one place it looks as
        # though a model did the scoring.
        # How this verdict was arrived at, beside the verdict itself. The
        # metadata pane has said "Type: LLM judge" all along, four screens'
        # worth of scrolling from the number it describes; a reader deciding
        # whether to argue with a score needs it where the score is.
        def method_badge
          Atoms::Badge.for_check_type(scoring_method, size: :sm)
        end

        def scoring_method
          @scoring_method ||= RAAF::Rails::ScoringMethod.for_result(@result, judged: judge_recorded?)
        end

        def head_meta
          [policy_name, @result.agent_name.presence, evaluator_fancy_name,
           (@result.model.presence if llm_judge?)].compact.join(" · ")
        end

        def head_stats
          [{ label: "Score", value: score_text(@result.score), tone: score_tone(@result.score) },
           { label: "Check", value: field_label },
           { label: "Scored", value: @result.created_at ? time_ago(@result.created_at) : "—" }]
        end

        # Where this verdict came from and what else it belongs to. The trace
        # rather than the span: every span row in this console opens its trace
        # with itself selected, so the run around it is readable too.
        def links
          div(class: "raaf-result-links") do
            trace = trace_span_path(@result.span_id, @result.trace_id)
            render Atoms::Link.new("open trace", href: trace, mono: true) if trace

            if @result.evaluation_policy
              render Atoms::Link.new(policy_name, mono: true,
                                     href: continuous_policy_path(@result.evaluation_policy))
            end

            if @result.evaluation_queue_item
              render Atoms::Link.new("queue item", mono: true,
                                     href: continuous_queue_item_path(@result.evaluation_queue_item))
            end

            render Atoms::Link.new("more from #{@result.agent_name}", mono: true,
                                   href: continuous_results_path(agent: @result.agent_name))
          end
        end

        # ── Check breakdown ───────────────────────────────────────────────

        def scorer_breakdown
          render(Organisms::Card.new(title: "Check breakdown", subtitle: breakdown_subtitle)) do
            if scorers.empty?
              render Molecules::EmptyState.new(
                icon: "sliders", title: "No score recorded",
                text: "This evaluation finished without a number — read the reasoning below."
              )
            else
              scorers.each { |scorer| scorer_row(scorer) }
            end

            scoring_rules
          end
        end

        def scorer_row(scorer)
          score = scorer[:score].to_f
          badge = (Atoms::Badge.for_check_type(scorer_type(scorer), size: :sm) if mixed_methods?)

          row = Molecules::MeterRow.new(
            name: scorer[:name].to_s.tr("_", " "),
            value: score_text(score),
            pct: (score * 100).round,
            tone: score_tone(score),
            sub: scorer[:note].presence,
            tip: "#{score_text(score)} of a possible 1.00"
          )

          # The block is what draws the space ahead of the name, so a bar with
          # nothing to put there is rendered without one.
          badge ? render(row) { render badge } : render(row)
        end

        # Said per bar only where the bars disagree. Four rules under one
        # header already carrying "Rule-based" would repeat it four times and
        # say nothing; a judge sitting among three rules is the case the
        # reader has to see, and then every bar is labelled so the odd one out
        # is read as a difference rather than as the only one worth marking.
        def mixed_methods?
          scoring_method == RAAF::Rails::ScoringMethod::MIXED
        end

        def scorer_type(scorer)
          RAAF::Rails::ScoringMethod.type_of(check_for(scorer[:key])) if scorer[:key].present?
        end

        def breakdown_subtitle
          count = scorers.size
          return nil if count.zero?
          return "one check, on #{field_plain_label}" if count == 1

          "#{pluralize(count, 'check')} on #{field_plain_label}"
        end

        # Prefer the individual evaluators behind the field, when the run kept
        # them: a check made of three judges reads as three bars, not as one
        # average with the disagreement hidden inside it.
        def scorers
          @scorers ||= detailed_scorers.presence || flat_scorers
        end

        def detailed_scorers
          return check_scorers if stored_checks.any?

          inner = field_result["details"] || field_result[:details]
          return [] unless inner.is_a?(Hash)

          inner.filter_map do |name, payload|
            next unless payload.is_a?(Hash)

            score = payload["score"] || payload[:score]
            next if score.nil?

            { name: name, key: "#{field_name}:#{name}", score: score,
              note: payload["reasoning"] || payload["message"] ||
                    payload[:reasoning] || payload[:message] }
          end
        end

        # One bar per evaluator, from the per-check results the job kept.
        def check_scorers
          stored_checks.filter_map do |name, check|
            score = check_value(check, "score")
            next if score.nil?

            { name: check_display_name("#{field_name}:#{name}"), key: "#{field_name}:#{name}",
              score: score, note: check_value(check, "message") }
          end
        end

        # `scores` is written as `{ field_name => score }`, so this is the
        # single bar for the field. Falls back to the result's own score for
        # rows written before that column was populated.
        def flat_scorers
          stored = @result.scores
          if stored.is_a?(Hash) && stored.any?
            return stored.filter_map do |name, score|
              { name: check_display_name(name), key: name, score: score } if score
            end
          end

          return [] if @result.score.nil?

          [{ name: field_label, key: field_name, score: @result.score }]
        end

        # ── The rule behind the bar ───────────────────────────────────────

        # A bar labelled `confidence` reading 1.00 is read as the agent's own
        # confidence, and is nothing of the kind: it is the share of the values
        # in that field that were numbers inside a declared range. The rule
        # that produced it — the name its author gave it, the sentence saying
        # what it asks, and the numbers it holds a value to — is declared on
        # the evaluator and reached no part of this screen, so a reader had the
        # verdict and no way to see what had been asked.
        #
        # Nothing is drawn for a check the evaluator cannot be read back from:
        # a renamed evaluator class, or a result older than the check it was
        # written by, leaves the bars as they were rather than inventing a rule
        # to put under them.
        def scoring_rules
          return lost_evaluator_note if declared_checks.empty?

          div(class: "raaf-measures") do
            render Molecules::SectionHeader.new(title: "How this scores", meta: rules_meta,
                                                size: :sm)
            declared_checks.each { |check| scoring_rule(check) }
          end
        end

        # Silence here reads as "this check has nothing to explain", which is
        # the one thing it does not mean. Said out loud only where the row
        # predates the checks being stored on it and the evaluator has since
        # gone; an evaluator that simply describes none of its checks says
        # nothing, because there is nothing missing.
        def lost_evaluator_note
          return unless @evaluator_lost

          div(class: "raaf-measures") do
            render Molecules::SectionHeader.new(title: "How this scores", size: :sm)
            render Atoms::Text.new(
              "The evaluator #{@result.evaluator_name} can no longer be read back, and this " \
              "result predates checks being stored on it, so what was asked of this field " \
              "is not recoverable.",
              size: :"body-sm", tone: :secondary, wrap: true
            )
          end
        end

        def scoring_rule(check)
          div(class: "raaf-measure") do
            # Named only where there are several to tell apart: one rule has
            # already been named by the bar it sits under.
            if declared_checks.size > 1
              render Molecules::SectionHeader.new(title: rule_title(check),
                                                  meta: rule_scorer_name(check), size: :sm)
            end

            if check[:description].present?
              render Atoms::Text.new(check[:description], size: :"body-sm", tone: :secondary, wrap: true)
            end

            pairs = rule_pairs(check)
            render Molecules::KeyValueList.new(pairs: pairs, mono: true) if pairs.any?
          end
        end

        def rule_title(check)
          check[:display_name].presence || rule_scorer_name(check)
        end

        # The evaluator that did the arithmetic, named where there is one of them
        # to name. It is what somebody reads the formula in when the figures
        # under it need explaining.
        def rules_meta
          declared_checks.one? ? rule_scorer_name(declared_checks.first) : nil
        end

        def rule_scorer_name(check)
          check[:evaluator_type].to_s.tr("_", " ")
        end

        # What the rule was given: the bounds, the thresholds, whatever else
        # the evaluator was configured with. Printed with the same labels and
        # units as the figures it produced, so the two lists read as a pair.
        def rule_pairs(check)
          measurement_pairs(check[:options])
        end

        # The checks this result's field was declared with: one per stored
        # check where the job kept them apart, otherwise the single one the
        # field names.
        def declared_checks
          @declared_checks ||=
            if stored_checks.any?
              stored_checks.keys.filter_map { |name| check_for("#{field_name}:#{name}") }
            else
              # Not `Array(...)`: a check is a Hash, and Array() would take it
              # apart into its pairs.
              [check_for(field_name)].compact
            end
        end

        # ── Reasoning and details ─────────────────────────────────────────

        # The evaluator's own rendering of what it found, when it defines one.
        def evaluation_details
          markdown = @result.details&.dig("formatted_markdown") ||
                     @result.details&.dig(:formatted_markdown)
          return if markdown.blank?

          render(Organisms::Card.new(title: "Evaluation details")) do
            div(class: "raaf-prose") do
              raw(safe(RAAF::Rails::Tracing::MarkdownRenderer.markdown_to_html(markdown)))
            end
          end
        end

        # A rule-based verdict is not prose. It is assembled upstream by
        # joining each check's message with "; " under an AND or an OR, and
        # each message joins its own figures with " | ". Printed back as one
        # paragraph, the four checks behind a score read as a single run-on
        # line and the reader has to re-parse the punctuation to see where one
        # ends. So it is taken apart along the same seams it was built from:
        # a row per check, its figures under it. A judge writes real prose and
        # carries none of these markers, so it is printed as written.
        def reasoning
          return if @result.reasoning.blank? && judge_reads.empty? && measurement_groups.empty?

          render(Organisms::Card.new(title: reasoning_title, subtitle: reasoning_subtitle)) do
            reasoning_prose
            judge_findings
            measurements
          end
        end

        def reasoning_prose
          return if @result.reasoning.blank?

          if reasoning_clauses.any?
            div(class: "raaf-reasoning") { reasoning_clauses.each { |clause| reasoning_clause(clause) } }
          else
            render Atoms::Text.new(@result.reasoning, tone: :secondary, wrap: true)
          end
        end

        def reasoning_title
          @result.evaluator_type.to_s == "llm_judge" ? "Judge reasoning" : "Reasoning"
        end

        def reasoning_subtitle
          case reasoning_scan[:combinator]
          when "AND" then "every check had to hold"
          when "OR" then "any one check was enough"
          else judge_reads.any? { |read| read[:criteria].any? } ? "criterion by criterion" : nil
          end
        end

        def reasoning_clause(clause)
          div(class: "raaf-reasoning-clause") do
            render Atoms::Dot.new(tone: clause[:tone], label: clause[:tag]&.downcase)
            div(class: "raaf-reasoning-body") do
              render Atoms::Text.new(clause[:headline], size: :"body-sm", tone: :secondary)
              next if clause[:facts].empty?

              ul(class: "raaf-reasoning-facts") do
                clause[:facts].each { |fact| li { fact } }
              end
            end
          end
        end

        def reasoning_clauses
          reasoning_scan[:clauses]
        end

        def reasoning_scan
          @reasoning_scan ||= scan_reasoning(@result.reasoning.to_s)
        end

        def scan_reasoning(text)
          combinator = text[/\A(AND|OR):\s*/, 1]
          body = combinator ? text.sub(/\A(AND|OR):\s*/, "") : text
          return { combinator: nil, clauses: [] } unless combinator || body.match?(VERDICT_TAG)

          { combinator: combinator, clauses: split_clauses(body).map { |clause| parse_clause(clause) } }
        end

        # Split before a verdict tag rather than on every semicolon: a check's
        # own message can contain one — an exception's text, most often — and
        # breaking there would turn one failure into two half-sentences.
        def split_clauses(body)
          return body.split(/;\s+(?=\[)/) if body.match?(/;\s+\[/)
          return body.split(/;\s+/) if body.include?("; ")

          [body]
        end

        def parse_clause(text)
          clause = text.strip
          tag = clause[VERDICT_TAG, 1]
          headline, *facts = clause.sub(VERDICT_TAG, "").split(" | ").map(&:strip).reject(&:empty?)

          { tag: tag, tone: clause_tone(tag), headline: headline.to_s, facts: facts }
        end

        def clause_tone(tag)
          return :idle if tag.nil?
          return :ok if GOOD_TAGS.include?(tag)
          return :bad if BAD_TAGS.include?(tag)

          :warn
        end

        # ── What the judge concluded ──────────────────────────────────────

        # A judge scores against criteria one at a time and writes a paragraph
        # per criterion saying why it scored what it did. That is the whole of
        # what makes a judge's number readable, and all of it used to arrive
        # here as two key-value cells: the summary set in a 220px monospace
        # column, and the criteria as `Array#inspect` — Ruby hash rockets,
        # every criterion's instructions repeated in full, cut off at 600
        # characters in the middle of a word. The reader could see that six
        # criteria had been weighed and could read about one and a half of
        # them.
        #
        # So it is drawn as what it is: the summary as prose, then a list with
        # a row per criterion carrying its score, the judge's reasoning, and —
        # folded away, because it is the same instruction every time and long
        # — what that criterion asked for.
        def judge_findings
          return if judge_reads.empty?

          div(class: "raaf-findings") do
            judge_reads.each { |read| judge_finding(read) }
          end
        end

        def judge_finding(read)
          div(class: "raaf-finding") do
            if read[:name] && judge_reads.size > 1
              render Molecules::SectionHeader.new(title: read[:name], meta: read[:meta], size: :sm)
            end

            if read[:conclusion].present?
              render Atoms::Text.new(read[:conclusion], tone: :secondary, wrap: true,
                                     class: "raaf-finding-summary")
            end

            criteria_list(read[:criteria]) if read[:criteria].any?
          end
        end

        # An ordered list rather than a stack of divs: a judge's criteria are
        # numbered upstream, and a reader on a screen reader is told how many
        # there are and which one they are in.
        def criteria_list(criteria)
          weighted = criteria.map { |criterion| criterion[:weight] }.uniq.size > 1

          ol(class: "raaf-criteria") do
            criteria.each { |criterion| criterion_item(criterion, weighted: weighted) }
          end
        end

        def criterion_item(criterion, weighted:)
          li(class: "raaf-criterion") do
            div(class: "raaf-criterion-head") do
              render Atoms::Dot.new(tone: score_tone(criterion[:score]),
                                    label: criterion_dot_label(criterion))
              span(class: "raaf-criterion-name") { criterion[:title] }
              if weighted && criterion[:weight]
                render Atoms::Mono.new("×#{format_measurement_float(criterion[:weight].to_f)}",
                                       tone: :muted)
              end
              render Atoms::Mono.new(score_text(criterion[:score]),
                                     tone: score_tone(criterion[:score]))
            end

            if criterion[:reasoning].present?
              render Atoms::Text.new(criterion[:reasoning], size: :"body-sm", tone: :secondary,
                                     wrap: true)
            end

            criterion_ask(criterion)
          end
        end

        # The criterion's own wording, kept behind a disclosure. It is written
        # for the judge rather than for a reader — the scoring bands spelled
        # out, the same shape repeated six times — and printed inline it buries
        # the one paragraph that is about this run. `details` needs no
        # JavaScript and is reachable from the keyboard as it stands.
        def criterion_ask(criterion)
          return if criterion[:description].blank?

          details(class: "raaf-criterion-ask") do
            summary { "what this criterion asks" }
            render Atoms::Text.new(criterion[:description], size: :"body-sm", tone: :muted,
                                   wrap: true)
          end
        end

        # Colour alone says nothing to a reader who cannot see it, and the
        # score beside the dot is a bare number. So the dot carries the verdict
        # in words.
        def criterion_dot_label(criterion)
          { ok: "met", warn: "partly met", bad: "not met",
            muted: "not scored" }[score_tone(criterion[:score])]
        end

        # What each judge behind this field wrote, grouped the way the
        # measurements below are: one read per stored check, or the single
        # check's own result where the job kept no separate copy.
        def judge_reads
          @judge_reads ||=
            if stored_checks.any?
              stored_checks.filter_map do |name, check|
                judge_read_for(check_display_name("#{field_name}:#{name}"), check)
              end
            else
              [judge_read_for(single_check_name, field_result)].compact
            end
        end

        def judge_read_for(name, check)
          details = check_value(check, "details")
          return nil unless details.is_a?(Hash)

          conclusion = (details["chain_of_thought"] || details[:chain_of_thought]).to_s
          criteria = criteria_rows(details["criteria_evaluation"] || details[:criteria_evaluation])
          return nil if conclusion.blank? && criteria.empty?

          { name: name&.to_s&.tr("_", " "),
            meta: criteria.any? ? pluralize(criteria.size, "criterion") : nil,
            conclusion: conclusion, criteria: criteria }
        end

        def criteria_rows(stored)
          Array(stored).filter_map do |criterion|
            next unless criterion.is_a?(Hash)

            description = criterion_field(criterion, "description").to_s.strip
            { title: criterion_title(criterion, description),
              description: description,
              reasoning: criterion_field(criterion, "reasoning").to_s.strip,
              score: criterion_field(criterion, "score"),
              weight: criterion_field(criterion, "weight") }
          end
        end

        # `criterion_1` names nothing. The criterion's first clause does — it
        # is written as a claim about the output, and what follows it is the
        # scoring instruction. So the row is headed with the claim, and the
        # instruction stays in the fold below.
        def criterion_title(criterion, description)
          headline = description[/\A[^.:—]+/].to_s.strip
          return headline.truncate(90) if headline.length >= 12

          criterion_field(criterion, "criterion").to_s.tr("_", " ").capitalize.presence ||
            "Criterion"
        end

        def criterion_field(criterion, key)
          criterion[key].nil? ? criterion[key.to_sym] : criterion[key]
        end

        # ── What the check measured ───────────────────────────────────────

        # Every evaluator records the figures it decided on — the value it
        # read, the threshold it held that value to, the baseline it compared
        # against — and none of them used to reach this screen. A latency
        # verdict arrived as one line, "Latency: 14411.3ms", with everything
        # behind it sitting in the row unread. So they are listed under the
        # prose: one list per check where a field was graded by several
        # evaluators, one list where it was graded by one.
        #
        # The judge's transcript is left out. It has its own section below,
        # and a prompt set as a key-value pair is unreadable.
        def measurements
          return if measurement_groups.empty?

          div(class: "raaf-measures") do
            measurement_groups.each { |group| measurement_group(group) }
          end
        end

        def measurement_group(group)
          div(class: "raaf-measure") do
            render Molecules::SectionHeader.new(title: group[:name], meta: group[:meta], size: :sm) if group[:name]
            render Molecules::KeyValueList.new(pairs: group[:pairs], mono: true)
          end
        end

        def measurement_groups
          @measurement_groups ||=
            if stored_checks.any?
              stored_checks.filter_map do |name, check|
                measurement_group_for(check_display_name("#{field_name}:#{name}"), check)
              end
            else
              [measurement_group_for(single_check_name, field_result)].compact
            end
        end

        # The one evaluator behind a single-check field, named as the job
        # recorded it, so the list is headed the same way a multi-check one is.
        def single_check_name
          return check_display_name(field_name) if check_for(field_name)

          recorded = @result.metadata&.dig("specific_evaluators") ||
                     @result.metadata&.dig(:specific_evaluators)
          Array(recorded).first.presence || @result.evaluator_name.presence
        end

        def measurement_group_for(name, check)
          pairs = measurement_pairs(check_value(check, "details"))
          return nil if pairs.empty?

          score = check_value(check, "score")
          { name: name&.to_s&.tr("_", " "),
            meta: score.nil? ? nil : score_text(score.to_f),
            pairs: pairs }
        end

        def measurement_pairs(details)
          return {} unless details.is_a?(Hash)

          details.each_with_object({}) do |(key, value), pairs|
            name = key.to_s
            next if MEASUREMENT_SKIP.include?(name)
            # A nested result carrying its own score is a check in its own
            # right, and is already drawn as a bar in the breakdown above.
            next if value.is_a?(Hash) && (value.key?("score") || value.key?(:score))

            pairs[measurement_label(name)] = measurement_value(name, value)
          end
        end

        # The unit is carried by the value, so a key that only names one — the
        # `_ms` of `max_ms` — loses it and reads as "Max: 90000 ms".
        def measurement_label(key)
          suffix = UNIT_SUFFIXES.find { |unit| key.end_with?(unit) && key != unit }
          (suffix ? key.delete_suffix(suffix) : key).tr("_", " ").capitalize
        end

        # An empty collection is a finding, and the strongest one a check makes:
        # `off_scale: []` says every value was on the scale, which is the whole
        # question. Rendered as blank it came out as an em dash, the same thing
        # the screen prints for a measurement that was never taken — so a clean
        # result and an unmeasured one read identically, and the reader has no
        # way to tell which they are looking at.
        def measurement_value(key, value)
          case value
          when nil, true, false then { nil => nil, true => "yes", false => "no" }[value]
          when Numeric then numeric_measurement(key, value)
          when String then value.truncate(600)
          when Array then value.empty? ? "none" : value.map { |item| inline_measurement(item) }.join(" · ").truncate(600)
          when Hash then hash_measurement(key, value)
          else value.to_s.truncate(600)
          end
        end

        # A measurement that arrived as a hash is a set of figures, and set as
        # JSON it is read as a blob: `{"good":0.75,"used":"bad (<0.5)"}` has to
        # be parsed by eye before it says anything. The same pairs, labelled
        # and separated, say it at a glance — and the thresholds a verdict
        # turned on are the pairs a reader is most often after.
        def hash_measurement(key, value)
          return "none" if value.empty?
          return threshold_measurement(value) if key == "thresholds" && value.key?("good")

          value.map { |name, inner| "#{name.to_s.tr('_', ' ')} #{inline_measurement(inner)}" }
               .join(" · ").truncate(600)
        end

        # Two bars and where the score landed between them, in that order —
        # the order they are read in, rather than the order the hash stores.
        def threshold_measurement(value)
          used = value["good"] ? value["used"] : nil
          bars = ["good ≥ #{value['good']}", ("average ≥ #{value['average']}" if value["average"])]
          (bars.compact + [("scored #{used}" if used.present?)].compact).join(" · ")
        end

        def inline_measurement(value)
          case value
          when String then value
          when Hash then value.map { |name, inner| "#{name}: #{inner}" }.join(", ")
          else value.inspect
          end
        end

        def numeric_measurement(key, value)
          unit = measurement_unit(key)
          number = value.is_a?(Float) ? format_measurement_float(value) : value.to_s
          unit ? "#{number} #{unit}" : number
        end

        # Four places keeps a score readable and a millisecond exact; a whole
        # number is printed as one rather than as "90000.0".
        def format_measurement_float(value)
          rounded = value.round(4)
          rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
        end

        # Units are a naming convention here rather than stored data: a key
        # ending in `_ms`, or naming a latency or a duration, is milliseconds.
        def measurement_unit(key)
          return "ms" if key.end_with?("_ms") || key.match?(/latency|duration/)
          return "USD" if key.end_with?("_usd") || key.include?("cost")
          return "tokens" if key.end_with?("_tokens")

          nil
        end

        # ── The stored result ─────────────────────────────────────────────

        # The evaluator's own result for this field, as the job stored it.
        def field_result
          @field_result ||= begin
            inner = @result.details&.dig("result")
            inner.is_a?(Hash) ? inner : {}
          end
        end

        # Each evaluator's own verdict, kept only where a field was graded by
        # more than one: a single check's result is `field_result` itself,
        # unmerged, so the job does not store it twice.
        def stored_checks
          @stored_checks ||= begin
            stored = @result.details&.dig("checks")
            stored.is_a?(Hash) ? stored : {}
          end
        end

        def check_value(check, key)
          return nil unless check.is_a?(Hash)

          check[key] || check[key.to_sym]
        end

        # ── The judge's own call ──────────────────────────────────────────

        # An LLM judge's score is an opinion, and the only way to weigh one is
        # to read what it was asked and what it said. The reasoning above is
        # the judge's summary of itself; this is the exchange it came out of.
        # Shown for anything that recorded a call, and for a judge that did
        # not — an evaluator typed rule-based can still run one judge among
        # its checks, and this row is that one check.
        def judge_call
          return unless judge_recorded? || @result.evaluator_type.to_s == "llm_judge"

          render(Organisms::Card.new(title: "Judge call", subtitle: judge_call_subtitle,
                                     flush: !judge_recorded?)) do
            if judge_recorded?
              judge_blocks
            else
              render Molecules::EmptyState.new(
                icon: "chat-square-text", title: "Call not recorded",
                text: "This judge kept no transcript, so what it was sent and what " \
                      "it answered are not on record."
              )
            end
          end
        end

        def judge_blocks
          if judge_prompt.present?
            render Molecules::PayloadBlock.new(role: "prompt to the judge", tone: :agent,
                                               body: judge_prompt)
          end

          if judge_response.present?
            render Molecules::PayloadBlock.new(role: "the judge's answer", tone: :llm,
                                               body: judge_response)
          end

          judge_fallback_note
        end

        # A judge that could not be reached, or answered something unparseable,
        # is silently replaced by a heuristic upstream. The score below it then
        # looks like a judgement and is not one, so the substitution is said
        # here rather than left to be inferred from a missing answer.
        def judge_fallback_note
          return if judge_fallback.blank?

          render Molecules::ErrorCallout.new(
            klass: "not judged",
            message: "#{judge_fallback.to_s.capitalize} — the score above came from a " \
                     "heuristic stand-in, not from the model."
          )
        end

        def judge_recorded?
          judge_prompt.present? || judge_response.present?
        end

        def judge_call_subtitle
          return nil unless judge_recorded?

          model = judge_model.presence
          model ? "sent to #{model}" : "what the judge was sent and what it returned"
        end

        # The judge writes its transcript into the evaluator's own details,
        # which the job stores whole under details.result.
        def judge_details
          @judge_details ||= begin
            details = check_value(field_result, "details")
            details.is_a?(Hash) ? details : {}
          end
        end

        def judge_prompt
          judge_details["judge_prompt"] || judge_details[:judge_prompt]
        end

        def judge_response
          judge_details["judge_response"] || judge_details[:judge_response]
        end

        def judge_fallback
          judge_details["judge_fallback"] || judge_details[:judge_fallback]
        end

        def judge_model
          judge_details["judge_model"] || judge_details[:judge_model]
        end

        # ── Payload ───────────────────────────────────────────────────────

        # Flush, because the tab strip is a rule across the card's whole width
        # rather than a control inside its body — the same pane the span
        # inspector reads its payload in. The panel below re-applies padding.
        def payload
          render(Organisms::Card.new(title: "Scored payload", subtitle: payload_subtitle,
                                     flush: true)) do
            if @span.nil?
              render Molecules::EmptyState.new(
                icon: "file-earmark-x", title: "Span not on record",
                text: "The span this graded has been pruned, so what the evaluator read " \
                      "cannot be shown."
              )
            else
              payload_pane
            end
          end
        end

        # Both halves are rendered, and the radio the tabs sit over decides
        # which one shows. A link would have to load the page again, landing
        # the reader back at the top of a result they were reading the middle
        # of; nothing here needs the server, so nothing here asks it.
        def payload_pane
          if payload_halves.empty?
            render Molecules::EmptyState.new(
              icon: "braces", title: "Nothing recorded",
              text: "The span carries no input or output attributes."
            )
            return
          end

          div(class: "raaf-scored#{' raaf-scored--tabbed' if tabbed?}") do
            if tabbed?
              payload_toggles
              payload_tabs
            end
            payload_halves.each { |half| payload_panel(half) }
          end
        end

        def tabbed?
          payload_halves.length > 1
        end

        # Both radios come before the strip and the panels, because every rule
        # that acts on them is a sibling selector reading forwards.
        def payload_toggles
          payload_halves.each do |half|
            input(type: "radio", name: "raaf-scored", id: toggle_id(half[:id]),
                  class: "raaf-scored-toggle raaf-sr-only",
                  **(half[:id] == payload_tab ? { checked: true } : {}))
          end
        end

        def toggle_id(half_id)
          "raaf-scored-#{half_id}"
        end

        def payload_subtitle
          return nil if @span.nil?

          "read from #{@span.span_id} · the evaluator saw this run, not a stored copy"
        end

        # The two halves stack to a screenful each, and only one of them is
        # ever the half a reader came for, so they are tabbed rather than
        # stacked. A span carrying only one of them gets no tab strip.
        def payload_halves
          @payload_halves ||= [
            payload_half("input", payload_input, :agent),
            payload_half("output", payload_output, :llm)
          ].compact
        end

        def payload_half(id, body, tone)
          return nil if body.blank?

          formatted = pretty_payload(body)
          { id: id, body: formatted, tone: tone,
            format: formatted.equal?(body) ? nil : "json" }
        end

        def payload_tab
          @payload_tab_id ||= begin
            ids = payload_halves.map { |half| half[:id] }
            ids.include?(@payload_tab) ? @payload_tab : ids.first
          end
        end

        # No :active — which tab looks chosen follows the checked radio, so
        # that it keeps following it after a click the server never hears of.
        def payload_tabs
          render Molecules::Tabs.new(
            class: "raaf-scored-tabs",
            items: payload_halves.map do |half|
              { label: half[:id].capitalize, for: toggle_id(half[:id]) }
            end
          )
        end

        # The tab already names the half, so a caption repeating it is dropped;
        # a lone half keeps its caption, having no tab to name it.
        def payload_panel(half)
          div(class: "raaf-scored-panel raaf-scored-panel--#{half[:id]}") do
            render Molecules::PayloadBlock.new(
              role: tabbed? ? nil : half[:id], body: half[:body],
              tokens: half[:format], tone: half[:tone]
            )
          end
        end

        # What the evaluator read, read the same way it read it: the evaluation
        # job takes the user turns of the recorded conversation as the input
        # and the agent's final answer as the output, so this reads those two
        # attributes rather than a set of generic names that agent spans never
        # carry — which is why this section used to sit empty over a span that
        # had a whole conversation in it.
        def payload_input
          user_turns.presence ||
            span_payload("initial_user_prompt", "conversation_messages", "input", "messages", "prompt")
        end

        def payload_output
          span_payload("final_agent_response", "output", "result", "response")
        end

        # The user's side of the conversation, which is the half the evaluator
        # was given. Several turns are set apart rather than run together.
        def user_turns
          messages = parse_json(span_payload("conversation_messages"))
          return nil unless messages.is_a?(Array)

          content = messages.filter_map do |message|
            next unless message.is_a?(Hash)
            next unless (message["role"] || message[:role]).to_s == "user"

            (message["content"] || message[:content]).presence
          end
          content.map(&:to_s).join("\n\n").presence
        end

        # A collector writes its attributes under its own component's prefix —
        # "agent.conversation_messages" for a core agent, the class name of a
        # DSL agent for a DSL one — so a name is matched on the end of the key
        # rather than spelled out in full. Its own placeholders for absent data
        # ("[]", "No result available") count as absent.
        def span_payload(*names)
          attributes = @span.span_attributes
          return nil unless attributes.is_a?(Hash)

          value = names.filter_map { |name| attributes[attribute_key(attributes, name)] }
                       .find { |candidate| payload_present?(candidate) }
          return nil if value.nil?

          value.is_a?(String) ? value : JSON.pretty_generate(value)
        rescue StandardError
          nil
        end

        def attribute_key(attributes, name)
          return name if attributes.key?(name)

          attributes.keys.find { |key| key.to_s.end_with?(".#{name}") }
        end

        # "No user message found" is a collector's way of writing nothing, and
        # printed as a payload it reads as the agent's own words.
        def payload_present?(value)
          return false if value.nil?
          return value.any? if value.is_a?(Array) || value.is_a?(Hash)
          return false unless value.is_a?(String)

          text = value.strip
          text.present? && PAYLOAD_PLACEHOLDERS.exclude?(text)
        end

        # An agent that answers in JSON has its whole answer on one line, and
        # a structured output read as one line is unreadable — the field that
        # was scored sits somewhere in the middle of it. Where the payload
        # parses as an object or an array it is printed indented; prose, and
        # anything else that only looks like JSON, is left exactly as the
        # evaluator read it.
        def pretty_payload(text)
          parsed = parse_json(text)
          return text unless parsed.is_a?(Hash) || parsed.is_a?(Array)

          JSON.pretty_generate(parsed)
        rescue StandardError
          text
        end

        def parse_json(text)
          return nil unless text.is_a?(String)

          JSON.parse(text)
        rescue JSON::ParserError
          nil
        end

        # ── Neighbours ────────────────────────────────────────────────────

        def sibling_results
          return if @sibling_results.blank?

          render(Organisms::Card.new(title: "Other results for this span",
                                     subtitle: "what the policies made of the same run",
                                     flush: true)) do
            @sibling_results.each { |result| neighbour_row(result, label: :check) }
          end
        end

        # What this check has been scoring lately.
        #
        # This asked "whether this verdict is the odd one out" and answered it
        # with recent results of the same policy — a set that is empty whenever
        # the policy has graded one span, and mixes different questions on
        # different scales whenever it is not. The comparable set is the same
        # check across spans, which is what makes a single number readable.
        def check_history
          return if @history.nil?

          render(Organisms::Card.new(title: "How this check usually scores",
                                     subtitle: history_subtitle, flush: true)) do |card|
            card.actions { all_results_link }

            flat_notice
            comparisons
            if @history.results.any?
              @history.results.each { |result| neighbour_row(result, label: :span) }
            else
              nothing_to_compare
            end
          end
        end

        # Where this verdict sits among them, said in words rather than left to
        # be worked out from six rows.
        def history_subtitle
          return repeats_subtitle unless @history.any?

          [counted(@history.count, "score"),
           @history.median && "median #{score_text(@history.median)}",
           rank_text].compact.join(" · ")
        end

        # A check with no other span has run once, or has run over and over on
        # this one. The second says nothing about how it scores and should not
        # be reported as if it did — but reported as nothing at all it makes a
        # check on its eighth run look like a check that has never run.
        def repeats_subtitle
          return "no other span for this check to be read against" if @history.repeat_count < 2

          "#{counted(@history.repeat_count, "run")} on this span · no other span yet"
        end

        def nothing_to_compare
          return no_other_span if @history.repeat_count < 2

          render Molecules::Alert.new(
            :info, title: "Only this span, graded #{counted(@history.repeat_count, "time")}",
            text: "#{repeat_agreement} That says the check repeats, not that it can " \
                  "tell two spans apart — #{check_display_name(field_name)} has graded " \
                  "no other span in the last 30 days."
          )
        end

        def repeat_agreement
          case @history.repeats_agree?
          when true then "Every run of it returned #{score_text(@result.score)}."
          when false then "The runs did not all agree."
          else "Only this run carried a score."
          end
        end

        def no_other_span
          render Molecules::EmptyState.new(
            icon: "clipboard-check", title: "Nothing to compare with",
            text: "#{check_display_name(field_name)} has graded no other span in the last 30 days."
          )
        end

        def rank_text
          rank = @history.rank
          return nil if rank.nil?

          case rank
          when 0.75.. then "this one is among its highest"
          when ..0.25 then "this one is among its lowest"
          else "this one is typical"
          end
        end

        # The two readings that turn a score into a judgement: what the check
        # said the last time it ran, and what it has been averaging. A verdict
        # of 0.62 is good news after 0.40 and bad news after 0.90, and the
        # number alone cannot say which.
        def comparisons
          rows = [previous_comparison, average_comparison].compact
          return if rows.empty?

          render Molecules::KeyValueList.new(layout: :rows, mono: true, flush: true, pairs: rows.to_h)
        end

        def previous_comparison
          delta = @history.delta_vs_previous
          return nil if delta.nil?

          ["vs last run", "#{score_text(@history.previous.score)} · #{change_text(delta)}"]
        end

        def average_comparison
          delta = @history.delta_vs_average
          return nil if delta.nil?

          ["vs running average", "#{score_text(@history.average)} over " \
                                 "#{counted(@history.earlier_count, 'span')} · #{change_text(delta)}"]
        end

        # A movement smaller than the console's own noise floor is the same
        # answer twice, and printing "+0.00" invites it to be read as a change.
        def change_text(delta)
          return "unchanged" if delta.abs < 0.005

          "%+.2f" % delta
        end

        # The one thing a single result can never show, and the thing most
        # worth knowing about a check that reads 1.00: that it has returned the
        # same number every time it has run, and so has separated nothing.
        def flat_notice
          return unless @history.flat?

          render Molecules::ErrorCallout.new(
            klass: "Never varies",
            message: "Every one of the #{@history.count} spans this check has graded scored " \
                     "#{score_text(@history.median)}. A check that has not answered two " \
                     "different things has not distinguished anything yet — which is worth " \
                     "knowing before this verdict is read as a pass."
          )
        end

        def all_results_link
          render Atoms::Button.new(label: "All results", size: :sm, icon: "list-ul",
                                   href: continuous_results_path(evaluator: @result.evaluator_name))
        end

        def neighbour_row(result, label:)
          render Molecules::ResultRow.new(
            href: continuous_result_path(result),
            title: neighbour_title(result, label), meta: neighbour_meta(result),
            status: result.status,
            value: score_text(result.score), value_tone: score_tone(result.score)
          )
        end

        def neighbour_title(result, label)
          return truncate_id(result.span_id) if label == :span

          neighbour_check_name(result)
        end

        def neighbour_meta(result)
          [titles.label(result.evaluator_name).presence,
           result.created_at && time_ago(result.created_at)].compact.join(" · ")
        end

        # A neighbour is named by the check that graded it, the way this
        # result's own header is: the two lines otherwise disagree on one
        # screen, which reads "Points Justified" at the top and lists the same
        # check as `talking points` underneath.
        #
        # The row's own record of what it declared answers first, so a
        # neighbour whose evaluator has since been renamed or deleted keeps the
        # name it ran under; the registry answers for rows written before the
        # checks were stored on them.
        def neighbour_check_name(result)
          field = field_of(result)
          return titles.label(result.evaluator_name) if field.empty?

          stored_check_name(result, field) || titles.check_label(result.evaluator_name, field)
        end

        def stored_check_name(result, field)
          stored = result.details&.dig("declared_checks")
          return nil unless stored.is_a?(Array)

          declared = stored.select { |check| check.is_a?(Hash) && check["field_name"].to_s == field }
          # Named only where one check owns the field: with several and no
          # type on the row to tell them apart, this would put another rule's
          # name over the score.
          declared.first&.dig("display_name").presence if declared.one?
        end

        def titles = @titles ||= EvaluatorTitles.new

        # ── Metadata ──────────────────────────────────────────────────────

        # What is worth saying about a run depends on the kind of run it was.
        # A rule-based evaluator calls no model, spends nothing and finishes
        # inside a millisecond; printed against the judge's rows it shows a
        # price of $0.0000, no tokens and a duration of 0ms, and every one of
        # those reads as a measurement that failed rather than as a column
        # that does not apply to it. So each kind contributes only the rows it
        # can fill: the judge its model, its bill and its tokens, a replayed
        # consistency check its replays and what they cost, and a rule-based
        # evaluator neither.
        def metadata
          render(Organisms::Card.new(title: "Evaluation metadata", flush: true)) do
            render(Molecules::KeyValueList.new(layout: :rows, mono: true, flush: true,
                                               pairs: metadata_pairs))
          end
        end

        def metadata_pairs
          common_metadata_pairs
            .merge(judge_metadata_pairs)
            .merge(replay_metadata_pairs)
            .compact
        end

        # True of every result, whatever graded it. A row nothing filled is
        # dropped rather than dashed: "Version —" says only that evaluators
        # do not declare one, which is not news about this run.
        def common_metadata_pairs
          {
            "Scored at" => timestamp(@result.created_at),
            "Duration" => duration_text,
            "Evaluator" => evaluator_fancy_name,
            "Type" => evaluator_type_label,
            "Version" => @result.evaluator_version.presence,
            "Graded model" => (graded_model if llm_judge?),
            "Environment" => @result.environment.presence,
            "Trace" => @result.trace_id.presence
          }
        end

        # The judge's own call, which only an LLM judge makes. Kept off a
        # rule-based row entirely: a cost of nought there is the arithmetic of
        # having made no call, and is indistinguishable from a judge whose
        # usage never came back.
        def judge_metadata_pairs
          return {} unless llm_judge?

          {
            "Judge model" => judge_metadata_model,
            "Judge cost" => judge_cost,
            "Judge tokens" => judge_tokens
          }
        end

        # A consistency check does not read the span it was handed and stop:
        # it either replays the agent or reaches back through history for
        # comparable runs, and both cost something the reader is entitled to
        # see. Driven by the recorded mode rather than by the evaluator's
        # type, because a policy can put a consistency check behind an
        # evaluator declared rule_based.
        def replay_metadata_pairs
          case run_mode
          when "replay"
            { "Mode" => "replayed the agent",
              "Replays" => replay_count,
              "Replay model" => run_metadata("replay_model"),
              "Replay cost" => replay_cost,
              "Fallback" => fallback_text }
          when "historical"
            { "Mode" => "compared with earlier runs",
              "Spans compared" => historical_count,
              "Fallback" => fallback_text }
          else
            {}
          end
        end

        # The same derivation the header badge is drawn from, so the pane and
        # the pill cannot say two different things about one row.
        def evaluator_type_label
          Atoms::Badge.check_type_label(scoring_method)
        end

        def llm_judge?
          @result.evaluator_type.to_s == "llm_judge" || judge_recorded?
        end

        # Whose output was graded, not what did the grading — the same
        # distinction the pane's other rows turn on, so the label carries it
        # rather than leaving "Model" beside "Judge model" to be told apart.
        #
        # Shown against a judge, where two models are in play and which one a
        # row means is a real question. A rule-based verdict has no model in
        # it at all: the rules read text that a model happens to have written,
        # and naming that model beside them invites reading it as the thing
        # that scored. The header still carries it for a reader who wants to
        # know whose output this was.
        def graded_model
          model = @result.model.presence
          provider = @result.provider.presence
          return nil unless model

          provider ? "#{model} (#{provider})" : model
        end

        # A rule-based check finishes in well under a millisecond, and its
        # share of a run split across four fields rounds to nought in an
        # integer column. "0ms" reads as a stopped clock, so a duration too
        # small to have been stored says so instead.
        def duration_text
          ms = @result.evaluation_duration_ms
          return nil if ms.nil?
          return "under 1ms" if ms < 1
          return "#{ms.round}ms" if ms < 1000

          "#{(ms / 1000.0).round(2)}s"
        end

        # What grading this cost. Absent rather than "$0.0000" when nothing
        # was billed: nought is also what a judge that failed to report its
        # usage would show.
        def judge_cost
          cost = @result.metrics&.dig("evaluation_cost").to_f
          return nil unless cost.positive?

          "$#{'%.4f' % cost}"
        end

        def judge_tokens
          usage = @result.metrics&.dig("evaluation_usage")
          return nil unless usage.is_a?(Hash)

          total = usage["total_tokens"] || usage.values.select { |v| v.is_a?(Numeric) }.sum
          return nil if total.to_i.zero?

          "#{delimited(total)} tok"
        end

        # The transcript names the model that answered; the metrics name every
        # model billed for. They agree for a single judge, and the metrics are
        # the fuller answer where a field was graded by several.
        def judge_metadata_model
          models = @result.metrics&.dig("evaluation_models")
          return models.join(", ") if models.is_a?(Array) && models.any?

          judge_model.presence
        end

        def run_mode
          run_metadata("mode").to_s
        end

        def replay_count
          count = run_metadata("successful_reruns")
          count && pluralize(count.to_i, "run")
        end

        def historical_count
          count = run_metadata("historical_spans_found")
          count && pluralize(count.to_i, "span")
        end

        def replay_cost
          cost = run_metadata("replay_cost_usd").to_f
          return nil unless cost.positive?

          "$#{'%.4f' % cost}"
        end

        # Why the mode above is not the mode that was asked for. A replay that
        # could not be made falls back to history silently, and the score then
        # answers a slightly different question than the policy set.
        def fallback_text
          reason = run_metadata("fallback_reason")
          return nil if reason.blank?

          reason.to_s.tr("_", " ")
        end

        def run_metadata(key)
          @result.metadata&.dig(key) || @result.metadata&.dig(key.to_sym)
        end

        # ── Timeline ──────────────────────────────────────────────────────

        # Only the moments that were actually recorded. A run whose evaluator
        # never stamped a start shows three entries rather than a fourth one
        # invented from the row's own timestamps.
        def timeline
          entries = timeline_entries
          return if entries.empty?

          render(Organisms::Card.new(title: "Timeline", flush: true)) do
            entries.each { |entry| timeline_row(entry) }
          end
        end

        def timeline_entries
          queued = @result.evaluation_queue_item&.created_at

          [{ icon: "record-circle", tone: :accent, text: "Queued for evaluation", at: queued },
           { icon: "cpu", tone: :accent, text: "Evaluation started",
             at: @result.evaluation_started_at },
           { icon: verdict_icon, tone: score_tone(@result.score),
             text: "Scored #{score_text(@result.score)} — #{@result.status}",
             at: @result.evaluation_completed_at },
           { icon: "check2-circle", tone: :ok, text: "Result recorded",
             at: @result.created_at }].select { |entry| entry[:at] }
        end

        def verdict_icon
          case @result.status.to_s
          when "good" then "check2-circle"
          when "average" then "dash-circle"
          when "error" then "exclamation-triangle"
          else "x-octagon"
          end
        end

        def timeline_row(entry)
          div(class: "raaf-result-event") do
            render Atoms::Icon.new(entry[:icon], size: :sm, tone: icon_tone(entry[:tone]))

            span(class: "raaf-result-event-body") do
              render Atoms::Text.new(entry[:text], size: :sm, wrap: true)
              render Atoms::Mono.new(timestamp(entry[:at]), tone: :muted)
            end
          end
        end

        # Icon::TONES speaks in semantic names; map the score tones onto it.
        def icon_tone(tone)
          { ok: :success, warn: :warning, bad: :danger, accent: :accent, muted: :muted }[tone]
        end

        # ── Evaluator metadata ────────────────────────────────────────────

        # The display names and descriptions an evaluator class declares, so a
        # screen can say "Groundedness" where the row says "groundedness_llm".
        # Best-effort: an evaluator that has since been renamed or removed
        # leaves the raw names, which are still true.
        def load_evaluator_metadata
          @evaluator_display_name = nil
          @evaluator_description = nil
          # What the row wrote down about the checks behind it. That is true of
          # the evaluator that scored it, where the class read back below
          # answers for the evaluator of the same name today.
          @evaluator_checks = stored_declared_checks
          @evaluator_lost = false

          return if @result.evaluator_name.blank?

          evaluator_class = RAAF::Eval::Continuous::EvaluatorDiscovery.build(
            { "name" => @result.evaluator_name }
          )

          @evaluator_display_name = evaluator_class.display_name if evaluator_class.respond_to?(:display_name)
          @evaluator_description = evaluator_class.description if evaluator_class.respond_to?(:description)

          return if @evaluator_checks.any?

          @evaluator_checks = evaluator_class.evaluated_checks if evaluator_class.respond_to?(:evaluated_checks)
        rescue StandardError
          # Only a loss where the row carries nothing of its own: a result
          # stored before this was written has no checks and no class to fall
          # back on, and the screen says so rather than looking as though the
          # checks had no descriptions.
          @evaluator_lost = @evaluator_checks.blank?
          nil
        end

        # Written as JSON, so the keys come back as strings while every reader
        # of a check here asks for symbols.
        def stored_declared_checks
          stored = @result.details&.dig("declared_checks") || @result.details&.dig(:declared_checks)
          return [] unless stored.is_a?(Array)

          stored.filter_map { |check| check.transform_keys(&:to_sym) if check.is_a?(Hash) }
        end

        def evaluator_fancy_name
          @evaluator_display_name.presence || @result.evaluator_name.to_s.tr("_", " ")
        end

        def field_name
          @field_name ||= @result.metadata&.dig("field_name").presence ||
                          @result.metadata&.dig(:field_name).presence ||
                          @result.details&.dig("field_name").presence
        end

        def field_label
          return evaluator_fancy_name if field_name.blank?

          check_display_name(field_name)
        end

        # The field as the agent's own output spells it, for the lines that
        # say where a figure was read from rather than what judged it.
        def field_plain_label
          field_name.to_s.tr("_", " ").presence || evaluator_fancy_name
        end

        # The field a result recorded, spelled as it was stored: this is a
        # lookup key, and the callers that print it name the check it belongs
        # to instead.
        def field_of(result)
          (result.metadata&.dig("field_name").presence ||
           result.details&.dig("field_name").presence).to_s
        end

        # A check is looked up among the ones its evaluator declares, by the
        # "original_field_path:evaluator_type" a policy names it with.
        #
        # A result is not written that way. The job stores one row per graded
        # field and records the field alone, so every lookup off a result
        # arrives here with no evaluator type and used to match nothing: the
        # screen fell back to the field's own name and to the evaluator's
        # description, which is why a rule called "Confidence In Range" showed
        # as `confidence`. A field with one declared check is therefore matched
        # on the field alone. With several, the type is what tells them apart
        # and a guess would put another rule's name under these figures, so the
        # check stays unnamed.
        def check_for(field)
          return nil if @evaluator_checks.blank?

          path, type = field.to_s.split(":", 2)
          declared = @evaluator_checks.select { |check| check[:field_name].to_s == path }
          return declared.find { |check| check[:evaluator_type].to_s == type } if type

          declared.first if declared.one?
        end

        # Falls back to the last segment rather than the whole key: an unnamed
        # stored check is spelled "confidence:value_range", and the field ahead
        # of the colon is already the heading it sits under.
        def check_display_name(field)
          check_for(field)&.dig(:display_name).presence ||
            field.to_s.split(":").last.to_s.tr("_", " ")
        end

        def check_description(field)
          check_for(field)&.dig(:description)
        end

        # ── Formatting ────────────────────────────────────────────────────

        # Null for a deleted policy and for a result nothing sampled alike —
        # see ResultsList#policy_name.
        def policy_name
          @result.evaluation_policy&.name.presence || "no policy"
        end
      end
    end
  end
end
