# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # One case an experiment scored: what went in, what was expected, what
      # the agent produced, and how each scorer graded it.
      #
      # No canvas draws this screen. RAAF Eval.dc.html stops at the results
      # table, which prints a hundred and sixty characters of output and no
      # way to read the rest — so a run's failures could be counted but not
      # examined. It is built on the Result screen from RAAF Continuous.dc.html
      # instead, which is the same object one level over: a verdict, the
      # scorers behind it, the payload it was passed, and its own metadata.
      #
      # One departure worth naming: the canvas's per-scorer weights and
      # thresholds are absent here as they are everywhere else in the console,
      # because an experiment stores a score per dimension and nothing about
      # how the dimensions were combined or what they had to clear.
      #
      class ExperimentResultShow < RAAF::Rails::Tracing::BaseComponent
        # @param neighbours [Hash] :previous and :next results in the run,
        #   either of which may be nil at the ends
        def initialize(experiment:, result:, neighbours: {})
          @experiment = experiment
          @result = result
          @item = result.dataset_item
          @neighbours = neighbours || {}
        end

        def view_template
          div(class: "raaf-page") do
            header
            div(class: "raaf-detail-split") do
              div(class: "raaf-stack") { main_column }
              div(class: "raaf-stack") { side_column }
            end
          end
        end

        private

        def main_column
          scores
          failure
          output
          expected
          input
        end

        def side_column
          metadata
          stepper
        end

        # ── Header ────────────────────────────────────────────────────────

        def header
          render Organisms::RecordHead.new(
            parent: { label: @experiment.name, href: eval_experiment_path(@experiment) },
            title: "Item ##{@result.dataset_item_id}", mono: true,
            description: item_description,
            status: @result.status,
            badges: [method_badge].compact,
            meta: head_meta,
            stats: head_stats
          )
        end

        # A dataset item carries no prose of its own, so the header says where
        # the case came from instead — a case promoted from production reads
        # differently from one somebody wrote.
        def item_description
          return nil if @item.nil?

          source = @item.source_span_id.presence ? "promoted from a production span" : "written by hand"
          "Case #{@result.dataset_item_id} of #{@experiment.dataset&.name} · #{source}"
        end

        # What graded the case, beside what it scored. An experiment mixes
        # checks from several evaluators freely, so this is as often "Mixed" as
        # it is one method — and where it is, each bar below says which it was.
        def method_badge
          Atoms::Badge.for_check_type(scoring_method, size: :sm)
        end

        def scoring_method
          @scoring_method ||= RAAF::Rails::ScoringMethod.of_checks(declared_checks)
        end

        def mixed_methods?
          scoring_method == RAAF::Rails::ScoringMethod::MIXED
        end

        def head_meta
          [@experiment.agent_name.presence, @experiment.model.presence,
           @experiment.provider.presence].compact.join(" · ")
        end

        def head_stats
          [{ label: "Score", value: score_text(@result.overall_score),
             tone: score_tone(@result.overall_score) },
           { label: "Duration", value: duration_text },
           { label: "Tokens", value: token_text }]
        end

        # ── Scores ────────────────────────────────────────────────────────

        def scores
          render(Organisms::Card.new(title: "Scores", subtitle: scores_subtitle)) do
            if dimensions.empty?
              render Molecules::EmptyState.new(
                icon: "sliders", title: "Not scored",
                text: not_scored_text
              )
            else
              dimensions.each { |name, value| score_row(name, value) }
              scoring_rules
            end
          end
        end

        # An experiment that named no scorers was never graded; one that named
        # them and came back with nothing was. The two look identical on the
        # screen and mean opposite things about whether to trust the run.
        def not_scored_text
          if @experiment.scorers.any? { |scorer| scorer[:enabled] }
            "This experiment names scorers, and none of them returned a number for this case."
          else
            "No scorer is switched on for this experiment, so nothing was measured."
          end
        end

        def score_row(name, value)
          score = value.to_f
          badge = (Atoms::Badge.for_check_type(dimension_type(name), size: :sm) if mixed_methods?)

          row = Molecules::MeterRow.new(
            name: check_label(name),
            value: score_text(score),
            pct: (score * 100).round,
            tone: score_tone(score),
            tip: "#{score_text(score)} of a possible 1.00"
          )

          # The block is what draws the space ahead of the name, so a bar with
          # nothing to put there is rendered without one.
          badge ? render(row) { render badge } : render(row)
        end

        # Named per bar only where the bars disagree: repeating one method down
        # a column of four says nothing, and the run where a judge sits among
        # three rules is the one the reader has to be able to see.
        def dimension_type(name)
          RAAF::Rails::ScoringMethod.type_of(check_for(name))
        end

        # A dimension is stored as `field:evaluator`, which names where the
        # number came from rather than what was asked. The check's own name
        # where the run recorded one.
        #
        # Without one the key is spelled out rather than run together:
        # "quality:value range" reads as one broken word, where "quality · value
        # range" reads as the field and the scorer that graded it, which is what
        # the key says.
        def check_label(name)
          declared = check_for(name)&.dig(:display_name).presence
          return declared if declared

          name.to_s.split(":").map { |part| part.tr("_", " ") }.join(" · ")
        end

        # ── The rule behind the bar ───────────────────────────────────────

        # What each check asks, under the bars it produced. Declared on the
        # evaluator and written onto the result when it was scored, so a case
        # keeps saying what it was held to however the evaluator changes after.
        def scoring_rules
          return if declared_checks.empty?

          div(class: "raaf-measures") do
            render Molecules::SectionHeader.new(title: "How this scores", size: :sm)
            declared_checks.each { |check| scoring_rule(check) }
          end
        end

        def scoring_rule(check)
          div(class: "raaf-measure") do
            render Molecules::SectionHeader.new(
              title: check[:display_name].presence || check[:field_name].to_s.tr("_", " "),
              meta: check[:evaluator_type].to_s.tr("_", " "), size: :sm
            )

            if check[:description].present?
              render Atoms::Text.new(check[:description], size: :"body-sm", tone: :secondary,
                                                          wrap: true)
            end

            pairs = rule_pairs(check)
            render Molecules::KeyValueList.new(pairs: pairs, mono: true) if pairs.any?
          end
        end

        # The bounds and thresholds the check was given, beside what it decided.
        def rule_pairs(check)
          options = check[:options]
          return {} unless options.is_a?(Hash)

          options.each_with_object({}) do |(key, value), pairs|
            pairs[key.to_s.tr("_", " ").capitalize] = value.to_s
          end
        end

        def check_for(name)
          field, type = name.to_s.split(":", 2)

          declared_checks.find do |check|
            check[:field_name].to_s == field && (type.nil? || check[:evaluator_type].to_s == type)
          end
        end

        # Written as JSON, so the keys come back as strings while every reader
        # here asks for symbols.
        def declared_checks
          @declared_checks ||= begin
            stored = @result.metadata&.dig("declared_checks") ||
                     @result.metadata&.dig(:declared_checks)
            stored.is_a?(Array) ? stored.filter_map { |c| c.transform_keys(&:to_sym) if c.is_a?(Hash) } : []
          end
        end

        # The overall score is the mean of these, which the card says out
        # loud: a single number over a list of bars invites the reading that
        # it came from somewhere else.
        def scores_subtitle
          return nil if dimensions.empty?
          return "one dimension" if dimensions.size == 1

          "#{pluralize(dimensions.size, 'dimension')} · overall is their mean"
        end

        def dimensions
          @dimensions ||= begin
            stored = @result.scores
            stored.is_a?(Hash) ? stored.select { |_, value| value.is_a?(Numeric) } : {}
          end
        end

        # ── Payloads ──────────────────────────────────────────────────────

        def failure
          return if @result.error_message.blank?

          render(Organisms::Card.new(title: "Failure")) do
            render Molecules::ErrorCallout.new(klass: @result.status.to_s,
                                               message: @result.error_message)
          end
        end

        def output
          render(Organisms::Card.new(title: "Output", flush: @result.output.blank?)) do
            if @result.output.blank?
              render Molecules::EmptyState.new(
                icon: "braces", title: "No output",
                text: "The run recorded nothing for this case."
              )
            else
              render Molecules::PayloadBlock.new(role: "agent output", tone: :llm,
                                                 body: pretty(@result.output))
            end
          end
        end

        def expected
          return if @item.nil? || @item.expected_output.blank?

          render(Organisms::Card.new(title: "Expected output",
                                     subtitle: "what the dataset says a correct answer is")) do
            render Molecules::PayloadBlock.new(role: "expected", tone: :ok,
                                               body: pretty(@item.expected_output))
          end
        end

        def input
          return if @item.nil? || @item.input.blank?

          render(Organisms::Card.new(title: "Input")) do
            render Molecules::PayloadBlock.new(role: "input", tone: :agent,
                                               body: pretty(@item.input))
          end
        end

        def pretty(value)
          return value.to_s if value.is_a?(String)

          JSON.pretty_generate(value)
        rescue StandardError
          value.to_s
        end

        # ── Metadata ──────────────────────────────────────────────────────

        def metadata
          render(Organisms::Card.new(title: "Run metadata", flush: true)) do
            render Molecules::KeyValueList.new(layout: :rows, mono: true, flush: true,
                                               pairs: metadata_pairs)
          end
        end

        def metadata_pairs
          {
            "Started" => @result.started_at && timestamp(@result.started_at),
            "Completed" => @result.completed_at && timestamp(@result.completed_at),
            "Duration" => duration_text,
            "Tokens" => token_text,
            "Latency" => latency_text,
            "Trace" => @result.result_trace_id.presence,
            "Span" => @result.result_span_id.presence
          }.compact
        end

        # ── Stepping through the run ──────────────────────────────────────

        # The table lists newest first; this walks the run in the order it
        # happened, which is the order a failure is usually chased in.
        def stepper
          previous = @neighbours[:previous]
          following = @neighbours[:next]
          return if previous.nil? && following.nil?

          render(Organisms::Card.new(title: "Elsewhere in this run", flush: true)) do
            step_row("Previous case", previous, "arrow-left") if previous
            step_row("Next case", following, "arrow-right") if following
            trace_row if @result.result_trace_id.present?
          end
        end

        def step_row(label, result, icon)
          render Molecules::ResultRow.new(
            href: eval_experiment_result_path(@experiment, result),
            title: "##{result.dataset_item_id}", meta: label, icon: icon,
            status: result.status,
            value: score_text(result.overall_score),
            value_tone: score_tone(result.overall_score)
          )
        end

        # What the agent actually did, which no amount of stored output
        # explains on its own.
        def trace_row
          href = trace_span_path(@result.result_span_id, @result.result_trace_id)
          return if href.nil?

          render Molecules::ResultRow.new(
            href: href, title: "open trace", meta: "the run behind this output",
            icon: "diagram-3", icon_tone: :accent
          )
        end

        # ── Formatting ────────────────────────────────────────────────────

        def duration_text
          seconds = @result.duration
          return "—" if seconds.nil?

          seconds < 1 ? "#{(seconds * 1000).round}ms" : "#{seconds.round(2)}s"
        end

        def token_text
          metrics = @result.token_metrics
          return "—" unless metrics.is_a?(Hash)

          total = metrics["total_tokens"] || metrics["total"]
          total ? "#{delimited(total)} tok" : "—"
        end

        def latency_text
          metrics = @result.latency_metrics
          return nil unless metrics.is_a?(Hash)

          ms = metrics["total_ms"] || metrics["latency_ms"] || metrics["duration_ms"]
          ms && "#{ms.to_i}ms"
        end
      end
    end
  end
end
