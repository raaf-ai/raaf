# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # One graded verdict, from the Result screen in RAAF Continuous.dc.html:
      # a header carrying the span, the verdict and the score; the scorer
      # breakdown, the judge's reasoning and the payload that was scored down
      # the left; the evaluation's own metadata, its timeline and its
      # neighbours down the right.
      #
      # Three departures from the canvas, all of them data rather than layout:
      #
      # - **No threshold marker.** The canvas draws each scorer's bar against
      #   the threshold it had to clear, and prints the composite's threshold
      #   under it. No threshold is stored on a policy, an evaluator or a
      #   result, so a marker here would be a line drawn at a number nobody
      #   set.
      # - **No findings list.** The canvas itemises what a scorer found — the
      #   entity, where in the output it sat, why it counted. An evaluator
      #   records a score and prose; the spans of text behind them are not
      #   kept, so the reasoning is the whole of what can be shown.
      # - **The payload is the span's, not a stored copy.** The canvas prints
      #   the input and output the scorer saw. A result stores neither, so
      #   this reads them off the span it graded, and says so when the span
      #   has since been pruned.
      #
      # One addition the canvas does not draw: an LLM judge's own call. Where
      # a rule-based scorer's verdict can be re-derived from the payload and
      # the rule, a judge's cannot be checked at all without reading what it
      # was asked and what it answered, so the exchange gets a section.
      #
      class ResultShow < RAAF::Rails::Tracing::BaseComponent
        # Above this a score is healthy, below the lower bound it is failing.
        # The tiers every other eval screen uses.
        GOOD = 0.8
        POOR = 0.5

        # @param span [RAAF::Rails::Tracing::SpanRecord, nil] the span that was
        #   graded, when it is still on record
        # @param sibling_results [Enumerable] the other results for this span
        # @param policy_results [Enumerable] recent results from this policy,
        #   for other spans
        def initialize(result:, span: nil, sibling_results: [], policy_results: [])
          @result = result
          @span = span
          @sibling_results = sibling_results
          @policy_results = policy_results
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
          policy_results
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
                   description: summary,
                   status: @result.status,
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
        def summary
          check_description(field_name).presence || @evaluator_description.presence
        end

        def head_meta
          [policy_name, @result.agent_name.presence, evaluator_fancy_name,
           @result.model.presence].compact.join(" · ")
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

        # ── Scorer breakdown ──────────────────────────────────────────────

        def scorer_breakdown
          render(Organisms::Card.new(title: "Scorer breakdown", subtitle: breakdown_subtitle)) do
            if scorers.empty?
              render Molecules::EmptyState.new(
                icon: "sliders", title: "No score recorded",
                text: "This evaluation finished without a number — read the reasoning below."
              )
            else
              scorers.each { |scorer| scorer_row(scorer) }
            end
          end
        end

        def scorer_row(scorer)
          score = scorer[:score].to_f

          render Molecules::MeterRow.new(
            name: scorer[:name].to_s.tr("_", " "),
            value: score_text(score),
            pct: (score * 100).round,
            tone: score_tone(score),
            sub: scorer[:note].presence,
            tip: "#{score_text(score)} of a possible 1.00"
          )
        end

        def breakdown_subtitle
          count = scorers.size
          return nil if count.zero?
          return "one scorer, on #{field_label}" if count == 1

          "#{pluralize(count, 'scorer')} on #{field_label}"
        end

        # Prefer the individual evaluators behind the field, when the run kept
        # them: a check made of three judges reads as three bars, not as one
        # average with the disagreement hidden inside it.
        def scorers
          @scorers ||= detailed_scorers.presence || flat_scorers
        end

        def detailed_scorers
          inner = @result.details&.dig("result")
          inner = inner.is_a?(Hash) ? (inner["details"] || inner[:details]) : nil
          return [] unless inner.is_a?(Hash)

          inner.filter_map do |name, payload|
            next unless payload.is_a?(Hash)

            score = payload["score"] || payload[:score]
            next if score.nil?

            { name: name, score: score,
              note: payload["reasoning"] || payload["message"] ||
                    payload[:reasoning] || payload[:message] }
          end
        end

        # `scores` is written as `{ field_name => score }`, so this is the
        # single bar for the field. Falls back to the result's own score for
        # rows written before that column was populated.
        def flat_scorers
          stored = @result.scores
          return stored.filter_map { |name, score| { name: name, score: score } if score } if stored.is_a?(Hash) && stored.any?
          return [] if @result.score.nil?

          [{ name: field_label, score: @result.score }]
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

        def reasoning
          return if @result.reasoning.blank?

          render(Organisms::Card.new(title: reasoning_title)) do
            render Atoms::Text.new(@result.reasoning, tone: :secondary, wrap: true)
          end
        end

        def reasoning_title
          @result.evaluator_type.to_s == "llm_judge" ? "Judge reasoning" : "Reasoning"
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
            inner = @result.details&.dig("result")
            details = inner.is_a?(Hash) ? (inner["details"] || inner[:details]) : nil
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

        def payload
          render(Organisms::Card.new(title: "Scored payload", subtitle: payload_subtitle,
                                     flush: @span.nil?)) do
            if @span.nil?
              render Molecules::EmptyState.new(
                icon: "file-earmark-x", title: "Span not on record",
                text: "The span this graded has been pruned, so what the scorer read " \
                      "cannot be shown."
              )
            else
              payload_blocks
            end
          end
        end

        def payload_subtitle
          return nil if @span.nil?

          "read from #{@span.span_id} · the scorer saw this run, not a stored copy"
        end

        def payload_blocks
          input = span_payload("input", "messages", "prompt")
          output = span_payload("output", "result", "response")

          render Molecules::PayloadBlock.new(role: "input", body: input, tone: :agent) if input
          render Molecules::PayloadBlock.new(role: "output", body: output, tone: :llm) if output

          return if input || output

          render Molecules::EmptyState.new(
            icon: "braces", title: "Nothing recorded",
            text: "The span carries no input or output attributes."
          )
        end

        # Span attributes are written under different keys by different span
        # kinds, so the first of the aliases that is present wins.
        def span_payload(*keys)
          attributes = @span.span_attributes
          return nil unless attributes.is_a?(Hash)

          value = keys.filter_map { |key| attributes[key] }.first
          return nil if value.nil?

          value.is_a?(String) ? value : JSON.pretty_generate(value)
        rescue StandardError
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

        def policy_results
          return if @result.evaluation_policy.blank?

          render(Organisms::Card.new(title: "Nearby results · same policy",
                                     subtitle: "whether this verdict is the odd one out",
                                     flush: true)) do |card|
            card.actions { all_results_link }

            if @policy_results.blank?
              render Molecules::EmptyState.new(
                icon: "clipboard-check", title: "Nothing else yet",
                text: "This policy has graded no other span."
              )
            else
              @policy_results.each { |result| neighbour_row(result, label: :span) }
            end
          end
        end

        def all_results_link
          render Atoms::Button.new(label: "All results", size: :sm, icon: "list-ul",
                                   href: continuous_results_path(policy: @result.evaluation_policy_id))
        end

        def neighbour_row(result, label:)
          a(href: continuous_result_path(result), class: "raaf-result-neighbour") do
            span(class: "raaf-result-neighbour-body") do
              render Atoms::Mono.new(neighbour_title(result, label))
              render Atoms::Mono.new(neighbour_meta(result), tone: :muted)
            end

            render Atoms::StatusBadge.new(result.status)
            render Atoms::Mono.new(score_text(result.score), tone: score_tone(result.score))
          end
        end

        def neighbour_title(result, label)
          return result.span_id.to_s.delete_prefix("span_").first(12) if label == :span

          field_of(result)
        end

        def neighbour_meta(result)
          [result.evaluator_name.presence&.tr("_", " "),
           result.created_at && time_ago(result.created_at)].compact.join(" · ")
        end

        # ── Metadata ──────────────────────────────────────────────────────

        def metadata
          render(Organisms::Card.new(title: "Evaluation metadata", flush: true)) do
            render(Molecules::KeyValueList.new(layout: :rows, mono: true,
                                               pairs: metadata_pairs))
          end
        end

        def metadata_pairs
          {
            "Scored at" => timestamp(@result.created_at),
            "Duration" => duration_text,
            "Evaluator" => evaluator_fancy_name,
            "Type" => evaluator_type_label,
            "Version" => @result.evaluator_version.presence || "—",
            "Model" => @result.model.presence || "—",
            "Provider" => @result.provider.presence || "—",
            "Environment" => @result.environment.presence || "—",
            "Trace" => @result.trace_id.to_s,
            "Judge cost" => judge_cost,
            "Judge tokens" => judge_tokens
          }.compact
        end

        def evaluator_type_label
          case @result.evaluator_type.to_s
          when "llm_judge" then "LLM judge"
          when "rule_based" then "Rule-based"
          else @result.evaluator_type.to_s.tr("_", " ").capitalize
          end
        end

        def duration_text
          ms = @result.evaluation_duration_ms
          return "—" if ms.nil?

          ms < 1000 ? "#{ms.round}ms" : "#{(ms / 1000.0).round(2)}s"
        end

        # What grading this cost, which only an LLM judge spends anything on.
        # Absent rather than "$0.00" for a rule-based scorer: nought is what a
        # judge that failed to bill would also show.
        def judge_cost
          cost = @result.metrics&.dig("evaluation_cost")
          return nil if cost.nil?

          "$#{'%.4f' % cost.to_f}"
        end

        def judge_tokens
          usage = @result.metrics&.dig("evaluation_usage")
          return nil unless usage.is_a?(Hash)

          total = usage["total_tokens"] || usage.values.select { |v| v.is_a?(Numeric) }.sum
          return nil if total.to_i.zero?

          "#{delimited(total)} tok"
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
           { icon: verdict_icon, tone: score_tone(@result.score) || :muted,
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
          @evaluator_checks = []

          return if @result.evaluator_name.blank?

          evaluator_class = RAAF::Eval::Continuous::EvaluatorDiscovery.build(
            { "name" => @result.evaluator_name }
          )

          @evaluator_display_name = evaluator_class.display_name if evaluator_class.respond_to?(:display_name)
          @evaluator_description = evaluator_class.description if evaluator_class.respond_to?(:description)
          @evaluator_checks = evaluator_class.evaluated_checks if evaluator_class.respond_to?(:evaluated_checks)
        rescue StandardError
          nil
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

        def field_of(result)
          field = result.metadata&.dig("field_name").presence ||
                  result.details&.dig("field_name").presence
          field.to_s.tr("_", " ").presence || result.evaluator_name.to_s.tr("_", " ")
        end

        # A field is recorded as "original_field_path:evaluator_type", which
        # is how a check is looked up among the ones its evaluator declares.
        def check_for(field)
          return nil if @evaluator_checks.blank?

          path, type = field.to_s.split(":", 2)
          @evaluator_checks.find do |check|
            check[:field_name].to_s == path && check[:evaluator_type].to_s == type
          end
        end

        def check_display_name(field)
          check_for(field)&.dig(:display_name).presence || field.to_s.tr("_", " ")
        end

        def check_description(field)
          check_for(field)&.dig(:description)
        end

        # ── Formatting ────────────────────────────────────────────────────

        def policy_name
          @result.evaluation_policy&.name.presence || "policy removed"
        end

        def score_text(score)
          return "—" if score.nil?

          # `format` is not Kernel's here — Phlex's element methods take the
          # name, so the operator form is the one that survives.
          "%.2f" % score.to_f
        end

        def score_tone(score)
          return nil if score.nil?

          case score.to_f
          when GOOD.. then :ok
          when POOR...GOOD then :warn
          else :bad
          end
        end

        def timestamp(time)
          return "—" if time.nil?

          time.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
        end

        def delimited(number)
          number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        end
      end
    end
  end
end
