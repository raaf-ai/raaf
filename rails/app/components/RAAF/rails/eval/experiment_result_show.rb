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
        # Above this a score is healthy, below the lower bound it is failing.
        GOOD = 0.8
        POOR = 0.5

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

        def breadcrumb
          render Molecules::Breadcrumb.new(items: [
                                             { label: "Experiments", href: eval_experiments_path },
                                             { label: @experiment.name,
                                               href: eval_experiment_path(@experiment) },
                                             { label: "Results",
                                               href: eval_experiment_results_path(@experiment) },
                                             { label: "##{@result.dataset_item_id}" }
                                           ])
        end

        def header
          render Organisms::RecordHead.new(
            title: "Item ##{@result.dataset_item_id}", mono: true,
            description: item_description,
            status: @result.status,
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
                text: "No scorer recorded a number for this case."
              )
            else
              dimensions.each { |name, value| score_row(name, value) }
            end
          end
        end

        def score_row(name, value)
          score = value.to_f

          render Molecules::MeterRow.new(
            name: name.to_s.tr("_", " "),
            value: score_text(score),
            pct: (score * 100).round,
            tone: score_tone(score),
            tip: "#{score_text(score)} of a possible 1.00"
          )
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
            render Molecules::KeyValueList.new(layout: :rows, mono: true, pairs: metadata_pairs)
          end
        end

        def metadata_pairs
          {
            "Started" => timestamp(@result.started_at),
            "Completed" => timestamp(@result.completed_at),
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
          a(href: eval_experiment_result_path(@experiment, result), class: "raaf-result-neighbour") do
            render Atoms::Icon.new(icon, size: :sm, tone: :muted)

            span(class: "raaf-result-neighbour-body") do
              render Atoms::Mono.new("##{result.dataset_item_id}")
              render Atoms::Mono.new(label, tone: :muted)
            end

            render Atoms::StatusBadge.new(result.status)
            render Atoms::Mono.new(score_text(result.overall_score),
                                   tone: score_tone(result.overall_score))
          end
        end

        # What the agent actually did, which no amount of stored output
        # explains on its own.
        def trace_row
          href = trace_span_path(@result.result_span_id, @result.result_trace_id)
          return if href.nil?

          a(href: href, class: "raaf-result-neighbour") do
            render Atoms::Icon.new("diagram-3", size: :sm, tone: :accent)

            span(class: "raaf-result-neighbour-body") do
              render Atoms::Mono.new("open trace")
              render Atoms::Mono.new("the run behind this output", tone: :muted)
            end
          end
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
          return nil if time.nil?

          time.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
        end

        def delimited(number)
          number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        end
      end
    end
  end
end
