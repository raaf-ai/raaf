# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # The newest spans this policy would grade, each with a button that
      # grades it now.
      #
      # The span detail page has offered this since the policies section was
      # added there, but only to somebody who had already found the span. From
      # the policy — where a prompt or a threshold was just changed — the way
      # to try it on real traffic was to go looking through the span list for
      # something the policy happens to match. This is that search, done once,
      # on the page where the question comes up.
      #
      # A run started here is manual: it grades every check the policy
      # declares, regardless of the sampling counter, and is exempt from the
      # daily cap, because somebody pressed a button and is entitled to an
      # answer. It bills like any other evaluation, which is why the panel
      # offers five spans and not the whole window.
      #
      # No canvas has this panel — `RAAF Continuous.dc.html` draws a policy as
      # its header, checks, configuration and trend, all of them readings. So
      # it follows the library the rest of that screen is built from rather
      # than inventing a look, and sits below the trend, leaving the designed
      # order intact.
      class MatchingSpansPanel < RAAF::Rails::Tracing::BaseComponent
        def initialize(policy:, spans: [])
          @policy = policy
          @spans = spans
          @results_by_span = load_results
          @queue_items_by_span = load_queue_items
        end

        # The panel is also where the evaluate button sends you back to, so it
        # needs a name the browser can scroll to.
        DOM_ID = "matching-spans"

        # How long the panel waits before looking again while an evaluation it
        # started is still queued or running.
        REFRESH_INTERVAL_MS = 5000

        def view_template
          attributes = { id: DOM_ID }
          if work_outstanding?
            attributes[:data] = {
              controller: "auto-refresh",
              auto_refresh_interval_value: REFRESH_INTERVAL_MS
            }
          end

          render(Organisms::Card.new(title: "Matching spans", subtitle: SUBTITLE,
                                     flush: true, **attributes)) do |card|
            card.actions { browse_link }

            if @spans.empty?
              empty_state
            else
              @spans.each { |record| span_row(record) }
            end
          end
        end

        SUBTITLE = "Grade one now instead of waiting for the sampler. " \
                   "A manual run ignores the sampling counter and the daily cap."

        # An evaluation started here is answered by a worker, so the row that
        # would show the grade is not written by the request that queued it.
        # Rather than leave somebody watching a page that will never change,
        # the panel reloads itself until every row it shows has an answer.
        #
        # A worker that dies mid-run leaves its row saying "running" for good,
        # and reloading every five seconds against that forever is worse than
        # showing a stale badge. So the wait is bounded: past this, the row is
        # not something anybody is still waiting for.
        WAITING_STATUSES = %w[pending running].freeze

        STALE_AFTER = 5.minutes

        # What this policy already said about this span, so a re-evaluation
        # can be compared with something rather than started blind.
        #
        # A policy stores one result per graded field, so the worst of them is
        # the summary worth showing: a span with one bad field among six good
        # ones is the interesting one, and reporting the newest row instead
        # would hide it whenever a good field happened to finish last.
        WORST_FIRST = %w[error bad average good].freeze

        private

        def browse_link
          return if @policy.agent_name.blank?

          render Atoms::Button.new(label: "Browse spans", size: :sm, icon: "layers",
                                   href: tracing_spans_path(search: @policy.agent_name))
        end

        def work_outstanding?
          @queue_items_by_span.values.any? do |item|
            WAITING_STATUSES.include?(item.status) && item.updated_at > STALE_AFTER.ago
          end
        end

        # One query for the whole panel rather than one per row: the newest
        # result this policy produced for each of these spans, which is what
        # decides between "Evaluate" and "Re-evaluate".
        def load_results
          return {} if @spans.empty?

          RAAF::Eval::Models::ContinuousEvaluationResult
            .where(span_id: @spans.map(&:span_id), evaluation_policy_id: @policy.id)
            .order(created_at: :desc)
            .group_by(&:span_id)
        end

        def load_queue_items
          return {} if @spans.empty?

          RAAF::Eval::Models::EvaluationQueueItem
            .where(span_id: @spans.map(&:span_id), evaluation_policy_id: @policy.id)
            .order(created_at: :desc)
            .index_by(&:span_id)
        end

        def empty_state
          render Molecules::EmptyState.new(
            icon: "inbox",
            title: "Nothing to grade",
            text: "No span from the last #{PolicySpanLookup::WINDOW.inspect} matches this " \
                  "policy. A span counts only when it recorded an agent response — there is " \
                  "nothing for an evaluator to read without one."
          )
        end

        def span_row(span_record)
          div(class: "raaf-matching-span") do
            div(class: "raaf-matching-span-body") do
              div(class: "raaf-cluster") do
                link_to(span_record.name.presence || truncate_id(span_record.span_id),
                        trace_span_path(span_record.span_id, span_record.trace_id),
                        class: "raaf-matching-span-name")
                render Atoms::Badge.for_status(span_record.status) if span_record.status.present?
                graded_badge(span_record)
              end

              render Atoms::Mono.new(row_meta(span_record), tone: :muted)
            end

            action(span_record)
          end
        end

        def row_meta(span_record)
          [truncate_id(span_record.span_id),
           span_record.start_time && time_ago(span_record.start_time),
           span_record.duration_ms && "#{span_record.duration_ms.round} ms"].compact.join(" · ")
        end

        def action(span_record)
          case @queue_items_by_span[span_record.span_id]&.status
          when "running" then running_indicator
          when "pending" then render Atoms::Badge.new("Pending", variant: :blue, icon: "hourglass-split")
          else evaluate_button(span_record)
          end
        end

        # Not a Turbo submit: the evaluate action answers a turbo_stream
        # request by replacing the span page's policies section, which does not
        # exist here. A plain POST takes its HTML branch instead, and return_to
        # names this panel rather than the policy page, so the redraw lands
        # where the button was pressed instead of at the top.
        def evaluate_button(span_record)
          graded = @results_by_span[span_record.span_id].present?

          form(action: evaluate_tracing_span_path(span_record.span_id, policy_id: @policy.id),
               method: "post", class: "raaf-inline-form", data: { turbo: "false" }) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            input(type: "hidden", name: "return_to",
                  value: "#{continuous_policy_path(@policy)}##{DOM_ID}")

            # A span this policy has never graded is the one worth pressing, so
            # it carries the accent and a re-run stays the quiet chip.
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

        def graded_badge(span_record)
          results = @results_by_span[span_record.span_id]
          return if results.blank?

          statuses = results.map(&:status)
          worst = WORST_FIRST.find { |status| statuses.include?(status) }
          return if worst.nil?

          # StatusBadge owns the verdict-to-colour mapping, good/average/bad
          # included, so this does not repeat it.
          render Atoms::StatusBadge.new(worst)
        end
      end
    end
  end
end
