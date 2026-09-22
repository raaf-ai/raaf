# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # One queued evaluation: what it was for, how far it got, and what it
      # produced.
      #
      # This reads `EvaluationQueueItem` — RAAF's own ledger of what it decided
      # to run — while the Queue screen reads SolidQueue, which is what a
      # worker actually did. The two count different things, so the header
      # says which one this is.
      #
      # It rendered in the light theme before this, which mattered because it
      # is where Retry lives.
      #
      class QueueShow < RAAF::Rails::Tracing::BaseComponent
        def initialize(queue_item:, results: [])
          @queue_item = queue_item
          @results = Array(results)
        end

        def view_template
          div(class: "raaf-page") do
            actions
            header
            error_card if @queue_item.error_message.present?
            results_card
            timeline_card
          end
        end

        RESULT_COLUMNS = [
          { label: "Evaluator", span: 2 },
          { label: "Verdict", span: 1 },
          { label: "Score", span: 0.8, align: :right }
        ].freeze

        private

        def actions
          render Molecules::RowActions.new(class: "raaf-page-actions", actions: [
            (retry_action if failed?),
            (cancel_action if in_flight?),
            span_action,
            (policy_action if @queue_item.evaluation_policy)
          ].compact)
        end

        def retry_action
          { label: "Retry", href: retry_continuous_queue_item_path(@queue_item), method: :post,
            confirm: "Run this evaluation again?" }
        end

        def cancel_action
          { label: "Cancel", href: cancel_continuous_queue_item_path(@queue_item), method: :post,
            tone: :danger, confirm: "Cancel this evaluation?" }
        end

        def span_action
          { label: "Open span", href: "/raaf/tracing/spans/#{@queue_item.span_id}" }
        end

        def policy_action
          { label: "Open policy", href: continuous_policy_path(@queue_item.evaluation_policy) }
        end

        def failed?
          @queue_item.status.to_s == "failed"
        end

        def in_flight?
          %w[pending running].include?(@queue_item.status.to_s)
        end

        # ── Header ────────────────────────────────────────────────────────

        def header
          render Organisms::RecordHead.new(
            parent: { label: "Queue", href: continuous_queue_index_path },
            title: @queue_item.span_id.to_s,
            mono: true,
            description: "From RAAF's own queue ledger. The Queue screen counts " \
                         "SolidQueue jobs, which is a different list.",
            status: @queue_item.status.to_s,
            meta: head_meta,
            stats: head_stats
          )
        end

        def head_meta
          [policy_name, "priority #{@queue_item.priority}",
           pluralize(@queue_item.attempts.to_i, "attempt")].compact.join(" · ")
        end

        def policy_name
          @queue_item.evaluation_policy&.name.presence
        end

        def head_stats
          [{ label: "Results", value: @results.size.to_s },
           { label: "Duration", value: duration_text }]
        end

        def duration_text
          return "—" unless @queue_item.completed_at && @queue_item.started_at

          "#{(@queue_item.completed_at - @queue_item.started_at).round(2)}s"
        end

        # ── Error ─────────────────────────────────────────────────────────

        def error_card
          render(Organisms::Card.new(title: "Why it failed")) do
            render Atoms::Text.new(@queue_item.error_message.to_s, tone: :secondary)
            backtrace if @queue_item.error_backtrace.present?
          end
        end

        # Behind a disclosure: a backtrace is what you open when the message
        # alone did not explain it, and it is longer than everything else on
        # the screen put together.
        def backtrace
          details(class: "raaf-disclosure") do
            summary { "Backtrace" }
            render Atoms::CodeBlock.new(@queue_item.error_backtrace.to_s, height: :tall)
          end
        end

        # ── Results ───────────────────────────────────────────────────────

        def results_card
          render(Organisms::Card.new(title: "Results", subtitle: results_subtitle, flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: RESULT_COLUMNS,
                     empty: { icon: "hourglass-split", title: "Nothing scored yet",
                              text: "Results appear here once the evaluation finishes." }
                   )) do |grid|
              @results.each { |result| result_row(grid, result) }
            end
          end
        end

        def results_subtitle
          return nil if @results.empty?

          "#{pluralize(@results.size, 'evaluator')} scored this span"
        end

        def result_row(grid, result)
          grid.row(href: continuous_result_path(result), cells: [
                     { value: result.evaluator_name.to_s, primary: true },
                     { value: Atoms::StatusBadge.new(result.status.to_s) },
                     { value: Atoms::Mono.new(score_text(result.score),
                                              tone: score_tone(result.score)), align: :right }
                   ])
        end

        # ── Timeline ──────────────────────────────────────────────────────

        # Three stamps rather than a drawn timeline: the interesting question
        # is which of them is missing, and a list of pairs answers it without
        # a graphic.
        def timeline_card
          render(Organisms::Card.new(title: "Timeline", flush: true)) do
            render Molecules::KeyValueList.new(pairs: timeline_pairs, layout: :rows,
                                               mono: true, flush: true)
          end
        end

        def timeline_pairs
          { "Created" => stamp(@queue_item.created_at),
            "Started" => stamp(@queue_item.started_at),
            "Completed" => stamp(@queue_item.completed_at) }
        end

        def stamp(time)
          time ? time.strftime("%Y-%m-%d %H:%M:%S") : "not yet"
        end
      end
    end
  end
end
