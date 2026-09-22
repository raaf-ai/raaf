# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # The policies that would grade this span, each with a button that
      # grades it now.
      #
      # MatchingSpansPanel answers this from the policy — given a policy,
      # which spans could it grade. This is the same question from the other
      # end, asked by somebody reading a trace: this run looks wrong, what
      # does the evaluator say about it. The old console offered it as
      # ApplicablePoliciesSection on the span page; the rebuild replaced that
      # page with the trace inspector and the button did not come along.
      #
      # A run started here is manual: it grades every check the policy
      # declares, including the ones whose trigger mode is Manual, and it
      # ignores the sampling counter and the daily cap, because somebody
      # pressed a button and is entitled to an answer. It bills like any
      # other evaluation.
      class SpanPoliciesPanel < RAAF::Rails::Tracing::BaseComponent
        # The panel is where the evaluate button sends you back to, so it
        # needs a name the browser can scroll to.
        DOM_ID = "span-policies"

        # How long the panel waits before looking again while an evaluation it
        # started is still queued or running.
        REFRESH_INTERVAL_MS = 5000

        WAITING_STATUSES = %w[pending running].freeze
        STALE_AFTER = 5.minutes

        # A policy stores one result per graded field, so the worst of them is
        # the summary worth showing: a span with one bad field among six good
        # ones is the interesting one.
        WORST_FIRST = %w[error bad average good].freeze

        # @param span [RAAF::Rails::Tracing::SpanRecord]
        def initialize(span:)
          @span = span
          @policies = load_policies
          @results_by_policy = load_results
          @queue_items_by_policy = load_queue_items
        end

        def view_template
          return unless available?
          return unless gradeable_kind?

          attributes = { id: DOM_ID }
          if work_outstanding?
            attributes[:data] = {
              controller: "auto-refresh",
              auto_refresh_interval_value: REFRESH_INTERVAL_MS
            }
          end

          render(Organisms::Card.new(title: "Evaluation policies", subtitle: SUBTITLE,
                                     flush: true, **attributes)) do |card|
            card.actions { browse_link }

            body
          end
        end

        SUBTITLE = "Grade this span now instead of waiting for the sampler. " \
                   "A manual run ignores the sampling counter and the daily cap."

        private

        def body
          if !response_recorded?
            no_response_state
          elsif evaluation_span?
            evaluation_span_state
          elsif @policies.empty?
            no_policies_state
          else
            @policies.each { |policy| policy_row(policy) }
          end
        end

        def browse_link
          render Atoms::Button.new(label: "All policies", size: :sm, icon: "clipboard-check",
                                   href: continuous_policies_path)
        end

        # ── Rows ──────────────────────────────────────────────────────────

        def policy_row(policy)
          div(class: "raaf-matching-span") do
            div(class: "raaf-matching-span-body") do
              div(class: "raaf-cluster") do
                a(href: continuous_policy_path(policy), class: "raaf-matching-span-name") do
                  plain policy.name
                end
                graded_badge(policy)
              end

              render Atoms::Mono.new(row_meta(policy), tone: :muted)
            end

            action(policy)
          end
        end

        # What this policy already said about this span, so a re-evaluation
        # can be compared with something rather than started blind. The badge
        # opens the newest result, which is the one the reader wants.
        def graded_badge(policy)
          results = @results_by_policy[policy.id]
          return if results.blank?

          worst = WORST_FIRST.find { |status| results.any? { |r| r.status == status } }
          return if worst.nil?

          a(href: continuous_result_path(results.first), class: "raaf-cluster") do
            render Atoms::StatusBadge.new(worst)
          end
        end

        def row_meta(policy)
          results = @results_by_policy[policy.id]
          graded = results&.first&.created_at

          [evaluator_names(policy).presence,
           graded ? "graded #{time_ago(graded)}" : "never graded"].compact.join(" · ")
        end

        # The evaluators this policy runs, named the way the policy list
        # names them: an evaluator is stored either as a bare name or as a
        # config hash, and both spellings are in the column.
        def evaluator_names(policy)
          Array(policy.evaluators).filter_map do |evaluator|
            evaluator.is_a?(Hash) ? (evaluator["name"] || evaluator[:name]) : evaluator
          end.join(", ")
        end

        def action(policy)
          case @queue_items_by_policy[policy.id]&.status
          when "running" then running_indicator
          when "pending" then render Atoms::Badge.new("Pending", variant: :blue, icon: "hourglass-split")
          else evaluate_button(policy)
          end
        end

        # Not a Turbo submit. The evaluate action answers with a redirect, and
        # `return_to` carries this panel's fragment, so a plain POST reloads the
        # trace scrolled to the button that was pressed. A Turbo visit restores
        # the scroll position it recorded before the submit instead, which puts
        # the reader back at the top of a long waterfall.
        def evaluate_button(policy)
          graded = @results_by_policy[policy.id].present?

          form(action: evaluate_tracing_span_path(@span.span_id, policy_id: policy.id),
               method: "post", class: "raaf-inline-form", data: { turbo: "false" }) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            input(type: "hidden", name: "return_to", value: return_to)

            # A policy that has never graded this span is the one worth
            # pressing, so it carries the accent and a re-run stays quiet.
            button(type: "submit",
                   class: "raaf-button raaf-button--sm#{' raaf-matching-span-go' unless graded}") do
              i(class: "bi bi-play-fill")
              plain(graded ? "Re-evaluate" : "Evaluate")
            end
          end
        end

        def running_indicator
          span(class: "raaf-matching-span-running") do
            render Atoms::Spinner.new(label: "Evaluating")
            plain "Running"
          end
        end

        def return_to
          return continuous_policies_path if @span.trace_id.blank?

          "#{tracing_trace_path(@span.trace_id)}?#{{ span: @span.span_id }.to_query}##{DOM_ID}"
        end

        # ── Empty states ──────────────────────────────────────────────────

        # Three ways this panel has nothing to offer, and they are not the
        # same news. Collapsing them into one "no policies" line is what makes
        # a reader conclude the feature is broken.
        def no_policies_state
          render Molecules::EmptyState.new(
            icon: "clipboard-check",
            title: "No policy grades this span",
            text: "No active policy matches #{agent_name}. A policy names the agents it " \
                  "grades, so one has to exist and be running before this span can be scored."
          )
        end

        def no_response_state
          render Molecules::EmptyState.new(
            icon: "inbox",
            title: "Nothing to grade",
            text: "This span recorded no agent response. An evaluator reads that response, " \
                  "so a run started here would fail rather than score."
          )
        end

        def evaluation_span_state
          render Molecules::EmptyState.new(
            icon: "arrow-repeat",
            title: "This span is an evaluation",
            text: "Grading an evaluator's own run would feed evaluation on itself, which " \
                  "measures nothing. The pipeline refuses these too."
          )
        end

        # ── Data ──────────────────────────────────────────────────────────

        def available?
          defined?(RAAF::Eval::Continuous::PolicyMatcher) &&
            defined?(RAAF::Eval::Models::EvaluationPolicy)
        end

        # Only agent spans carry a response, and PolicySpanLookup narrows to
        # them for the same reason. On a tool or LLM span the panel would say
        # "nothing to grade" on every one of them, which is noise rather than
        # news, so it is absent instead.
        def gradeable_kind?
          @span.kind.to_s == "agent"
        end

        def response_recorded?
          attributes[PolicySpanLookup::RESPONSE_KEY].present?
        end

        def evaluation_span?
          attributes["source"].to_s == "evaluation_run"
        end

        def attributes
          @attributes ||= @span.span_attributes || {}
        end

        def agent_name
          attributes["agent.name"].presence ||
            attributes.dig("agent", "name").presence ||
            @span.display_name
        end

        # The matcher is not reimplemented here: this asks it the question it
        # was built to answer, so the panel cannot come to disagree with what
        # the pipeline does. It returns active policies only — a paused one
        # grades nothing, and offering its button would be a lie.
        def load_policies
          return [] unless available?
          return [] unless @span.kind.to_s == "agent"

          RAAF::Eval::Continuous::PolicyMatcher.new(@span).matching_policies
        rescue StandardError => e
          ::Rails.logger.warn "[SpanPoliciesPanel] Could not match policies: #{e.message}"
          []
        end

        # One query for the whole panel rather than one per row: every result
        # any of these policies produced for this span, newest first, which is
        # what decides between "Evaluate" and "Re-evaluate".
        def load_results
          return {} if @policies.empty?

          RAAF::Eval::Models::ContinuousEvaluationResult
            .where(span_id: @span.span_id, evaluation_policy_id: @policies.map(&:id))
            .order(created_at: :desc)
            .group_by(&:evaluation_policy_id)
        rescue StandardError
          {}
        end

        def load_queue_items
          return {} if @policies.empty?

          RAAF::Eval::Models::EvaluationQueueItem
            .where(span_id: @span.span_id, evaluation_policy_id: @policies.map(&:id))
            .order(created_at: :desc)
            .index_by(&:evaluation_policy_id)
        rescue StandardError
          {}
        end

        def work_outstanding?
          @queue_items_by_policy.values.any? do |item|
            WAITING_STATUSES.include?(item.status) && item.updated_at > STALE_AFTER.ago
          end
        end
      end
    end
  end
end
