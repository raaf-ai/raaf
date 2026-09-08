# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Controller for browsing evaluation results
      class ResultsController < BaseController
        # Alias the models for cleaner code
        EvaluationResult = RAAF::Eval::Models::ContinuousEvaluationResult

        # The window the Results screen's "worst evaluators" panel reports over,
        # and the window it compares that against for the delta.
        SCORER_WINDOW = 24.hours

        # How many buckets the score distribution is drawn in, matching the
        # ten the canvas draws: 0.0–0.1 up to 0.9–1.0.
        BUCKETS = 10

        # Score rounds into its bucket by tenths, except a perfect 1.0, which
        # would land in an eleventh bucket of its own.
        BUCKET_SQL = "LEAST(FLOOR(score * #{BUCKETS}), #{BUCKETS - 1})"

        # GET /raaf/rails/continuous/results
        def index
          # The panels above the table describe the population the chips
          # filter, so they are scoped by every filter *except* the status
          # chip. With it applied a bad-only table could only ever draw a
          # verdict split reading "bad, 100%", which answers nothing.
          population = filtered(EvaluationResult.all)

          @results = filtered(EvaluationResult.order(created_at: :desc))
          @results = @results.where(status: params[:status]) if params[:status].present?
          @results = @results.page(params[:page]).per(50)

          @summary = summary_for(population)
          @distribution = distribution_for(population)
          @worst_scorers = worst_scorers_for(population)
          @set_aside_scorers = instrument_failures_in(population, Time.current - SCORER_WINDOW, Time.current)

          # Filter options
          @agents = EvaluationResult.distinct.pluck(:agent_name).compact.sort
          @environments = EvaluationResult.distinct.pluck(:environment).compact.sort
          @evaluators = EvaluationResult.distinct.pluck(:evaluator_name).compact.sort
          @policies = policy_options

          respond_to do |format|
            format.html do
              results_list = RAAF::Rails::Continuous::ResultsList.new(
                results: @results,
                agents: @agents,
                policies: @policies,
                summary: @summary,
                distribution: @distribution,
                worst_scorers: @worst_scorers,
                scorer_window: "24h",
                set_aside_scorers: @set_aside_scorers,
                filters: params.permit(:agent, :environment, :status, :evaluator, :policy, :from, :to)
                               .to_h.symbolize_keys
              )
              render_in_layout results_list, title: "Results", crumb: "Continuous"
            end
            format.json { render json: @results }
          end
        end

        # GET /raaf/rails/continuous/results/:id
        def show
          @result = EvaluationResult.find(params[:id])
          @span = RAAF::Rails::Tracing::SpanRecord.find_by(span_id: @result.span_id)

          # Two neighbourhoods, because they answer different questions. The
          # other results for this span say what else the policies made of the
          # same run; the recent results for this policy say whether this
          # verdict is the odd one out or the shape of the whole stream.
          @sibling_results = EvaluationResult.where(span_id: @result.span_id)
                                             .where.not(id: @result.id)
                                             .order(created_at: :desc)
                                             .limit(20)
          # What this check has scored elsewhere, which is the only set that
          # makes one verdict readable — see CheckHistory.
          @history = RAAF::Rails::Continuous::CheckHistory.new(result: @result)

          respond_to do |format|
            format.html do
              result_show = RAAF::Rails::Continuous::ResultShow.new(
                result: @result, span: @span,
                sibling_results: @sibling_results,
                payload_tab: params[:payload], history: @history
              )
              render_in_layout result_show, title: "Result ##{@result.id}", crumb: "Continuous"
            end
            format.json { render json: @result }
          end
        end

        private

        # Everything the reader narrowed to except the status chip.
        #
        # A policy is filtered by id rather than by name: two policies may
        # carry the same name, and the id is what the policy page links with.
        def filtered(scope)
          scope = scope.where(evaluation_policy_id: params[:policy]) if params[:policy].present?
          scope = scope.where(agent_name: params[:agent]) if params[:agent].present?
          scope = scope.where(environment: params[:environment]) if params[:environment].present?
          scope = scope.where(evaluator_name: params[:evaluator]) if params[:evaluator].present?
          scope = scope.where("created_at >= ?", params[:from].to_date) if params[:from].present?
          scope = scope.where("created_at <= ?", params[:to].to_date.end_of_day) if params[:to].present?
          scope
        end

        # Counts per verdict, plus the median of the scores behind them.
        #
        # The median rather than the mean: the distribution the panel beside
        # it draws is nearly always piled against 1.0, and a mean is dragged
        # around by the handful of zeroes in a way that misreports the middle.
        def summary_for(population)
          counts = population.group(:status).count

          { total: counts.values.sum,
            good: counts["good"].to_i,
            average: counts["average"].to_i,
            bad: counts["bad"].to_i,
            error: counts["error"].to_i,
            scored: population.where.not(score: nil).count,
            median: median_score(population) }
        end

        # The lower median, by offset rather than by a percentile function:
        # `PERCENTILE_CONT` is PostgreSQL's, and the console is expected to
        # run on whatever the host application's database is.
        def median_score(population)
          scored = population.where.not(score: nil)
          count = scored.count
          return nil if count.zero?

          scored.reorder(:score).offset((count - 1) / 2).limit(1).pick(:score)&.to_f
        end

        # One entry per tenth, in order, including the tenths nothing landed
        # in — a histogram with its empty buckets dropped is a different
        # shape, not a shorter one.
        def distribution_for(population)
          counts = population.where.not(score: nil)
                             .group(Arel.sql(BUCKET_SQL)).count
                             .transform_keys(&:to_i)

          (0...BUCKETS).map do |bucket|
            low = bucket.to_f / BUCKETS
            { label: format("%.1f", low), low: low, high: low + (1.0 / BUCKETS),
              count: counts[bucket].to_i }
          end
        end

        # The evaluators doing worst over the window, with how far each moved
        # against the window before it. An evaluator that graded nothing in the
        # preceding window has no delta rather than a delta of zero: it did
        # not hold steady, it was not measured.
        def worst_scorers_for(population, limit: 4)
          now = Time.current
          current = means_by_evaluator(population, now - SCORER_WINDOW, now)
          return [] if current.empty?

          previous = means_by_evaluator(population, now - (SCORER_WINDOW * 2), now - SCORER_WINDOW)

          current.sort_by { |_, stats| stats[:average] }.first(limit).map do |name, stats|
            before = previous[name]
            { name: name, average: stats[:average], count: stats[:count],
              delta: before && (stats[:average] - before[:average]) }
          end
        end

        # Where an evaluator stores its own failure as a verdict. The DSL's
        # error_result writes label "bad" with score 0.0 and the message under
        # this path, so a check that could not read the field it was pointed at
        # is indistinguishable, by score alone, from an agent that fails every
        # time. Both arrive as a 0.00.
        INSTRUMENT_FAILURE_PATH = "{result,details,error}"

        def means_by_evaluator(population, from, to)
          window = scored_in(population, from, to)
          averages = window.group(:evaluator_name).average(:score)
          counts = window.group(:evaluator_name).count

          averages.each_with_object({}) do |(name, average), out|
            out[name] = { average: average.to_f, count: counts[name].to_i }
          end
        end

        # Rows that say something about the agent, which is not every scored row.
        #
        # An evaluator that raised, or that was pointed at a field the span does
        # not carry, records a 0.0 like any other verdict. Averaged in, those
        # rows put whichever check is broken at the top of a panel headed "worst
        # evaluators", and the reader is sent to fix an agent that may be fine —
        # which is what this panel did until 2026-09-08, when its four worst
        # entries were four broken checks.
        #
        # They are excluded rather than shown lower down: an instrument failure
        # has no score, and giving it one anywhere on this list is the mistake.
        # The count travels out so the panel can say they were set aside.
        def scored_in(population, from, to)
          population.where(created_at: from...to)
                    .where.not(score: nil)
                    .where("details #> ? IS NULL", INSTRUMENT_FAILURE_PATH)
        end

        # How many rows the window set aside as instrument failures, so the
        # panel can report the exclusion instead of quietly applying it.
        def instrument_failures_in(population, from, to)
          population.where(created_at: from...to)
                    .where.not(score: nil)
                    .where("details #> ? IS NOT NULL", INSTRUMENT_FAILURE_PATH)
                    .count
        end

        # The policies that have actually produced a result, as `[name, id]`.
        # A policy that has graded nothing is left out: choosing it could only
        # ever empty the table, and the filter is for narrowing rows that
        # exist rather than for browsing the policy list.
        def policy_options
          graded = EvaluationResult.distinct.pluck(:evaluation_policy_id).compact
          return [] if graded.empty?

          RAAF::Eval::Models::EvaluationPolicy.where(id: graded)
                                              .order(:name)
                                              .pluck(:name, :id)
        end
      end
    end
  end
end
