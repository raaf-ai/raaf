# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Controller for managing evaluation policies
      class PoliciesController < BaseController
        # Alias the model for cleaner code
        EvaluationPolicy = RAAF::Eval::Models::EvaluationPolicy

        before_action :set_policy, only: %i[show edit update destroy activate deactivate duplicate]

        # GET /raaf/rails/continuous/policies
        def index
          @policies = EvaluationPolicy.order(created_at: :desc)
          @policies = @policies.where(active: params[:active] == "true") if params[:active].present?
          @policies = @policies.where("agent_name ILIKE ?", "%#{params[:agent]}%") if params[:agent].present?
          @policies = @policies.page(params[:page]).per(50)

          respond_to do |format|
            format.html do
              policy_list = RAAF::Rails::Continuous::PolicyList.new(
                policies: @policies,
                stats: policy_stats,
                last_runs: last_run_times(@policies),
                params: params.permit(:active, :agent, :page)
              )
              # No range passed: this list is not filtered by time, and a pill
              # that navigates without changing the rows is worse than an
              # inert one.
              render_in_layout policy_list, title: "Policies", crumb: "Continuous"
            end
            format.json { render json: @policies }
          end
        end

        # GET /raaf/rails/continuous/policies/:id
        def show
          @recent_results = @policy.continuous_evaluation_results.order(created_at: :desc).limit(10)
          @today_stats = calculate_today_stats
          @matching_spans = RAAF::Rails::Continuous::PolicySpanLookup.recent_for(@policy)

          respond_to do |format|
            format.html do
              policy_show = RAAF::Rails::Continuous::PolicyShow.new(
                policy: @policy,
                today_stats: @today_stats,
                recent_results: @recent_results,
                matching_spans: @matching_spans,
                check_scores: check_scores(@policy),
                trend: trend_series(@policy, current_range),
                trend_window: TREND_WINDOWS.fetch(current_range),
                trend_unit: TREND_BUCKETS.fetch(current_range)[:unit]
              )
              render_in_layout policy_show, title: @policy.name, crumb: "Policy", range: current_range,
                                            range_href: range_href
            end
            format.json { render json: @policy }
          end
        end

        # GET /raaf/rails/continuous/policies/new
        def new
          @policy = EvaluationPolicy.new(default_policy_attributes)
          @available_evaluators = fetch_available_evaluators

          respond_to do |format|
            format.html do
              policy_form = RAAF::Rails::Continuous::PolicyForm.new(
                policy: @policy,
                evaluators: @available_evaluators
              )
              render_in_layout policy_form, title: "New Evaluation Policy", live: false
            end
          end
        end

        # GET /raaf/rails/continuous/policies/:id/edit
        def edit
          @available_evaluators = fetch_available_evaluators

          respond_to do |format|
            format.html do
              policy_form = RAAF::Rails::Continuous::PolicyForm.new(
                policy: @policy,
                evaluators: @available_evaluators
              )
              render_in_layout policy_form, title: "Edit #{@policy.name}", live: false
            end
          end
        end

        # POST /raaf/rails/continuous/policies
        def create
          @policy = EvaluationPolicy.new(policy_params)
          reject_cross_agent_checks(@policy)

          if @policy.errors.empty? && @policy.save
            redirect_to continuous_policy_path(@policy), notice: "Policy created successfully."
          else
            @available_evaluators = fetch_available_evaluators
            policy_form = RAAF::Rails::Continuous::PolicyForm.new(
              policy: @policy,
              evaluators: @available_evaluators
            )
            render_in_layout policy_form, title: "New Evaluation Policy", live: false,
                                          status: :unprocessable_content
          end
        end

        # PATCH /raaf/rails/continuous/policies/:id
        def update
          @policy.assign_attributes(policy_params)
          reject_cross_agent_checks(@policy)

          if @policy.errors.empty? && @policy.save
            redirect_to continuous_policy_path(@policy), notice: "Policy updated successfully."
          else
            @available_evaluators = fetch_available_evaluators
            policy_form = RAAF::Rails::Continuous::PolicyForm.new(
              policy: @policy,
              evaluators: @available_evaluators
            )
            render_in_layout policy_form, title: "Edit #{@policy.name}", live: false,
                                          status: :unprocessable_content
          end
        end

        # DELETE /raaf/rails/continuous/policies/:id
        def destroy
          @policy.destroy
          redirect_to continuous_policies_path, notice: "Policy deleted."
        end

        # POST /raaf/rails/continuous/policies/:id/activate
        #
        # Both toggles return to the page the button was pressed on: the list
        # and the policy screen each carry one, and being thrown back to the
        # list after pausing from the policy screen loses your place.
        def activate
          @policy.update!(active: true)
          redirect_back_or_to(continuous_policies_path, notice: "Policy resumed.")
        end

        # POST /raaf/rails/continuous/policies/:id/deactivate
        def deactivate
          @policy.update!(active: false)
          redirect_back_or_to(continuous_policies_path, notice: "Policy paused.")
        end

        # POST /raaf/rails/continuous/policies/:id/duplicate
        def duplicate
          new_policy = @policy.dup
          new_policy.name = "#{@policy.name} (Copy)"
          new_policy.active = false
          new_policy.save!
          redirect_to edit_continuous_policy_path(new_policy), notice: "Policy duplicated."
        end

        private

        # Counted over every policy, not the filtered page: the headline says
        # what the system is doing, and a filter should not change that.
        def policy_stats
          all = EvaluationPolicy.all

          { total: all.count,
            active: all.where(active: true).count,
            evaluated_today: all.sum(:today_evaluation_count),
            daily_cap: all.sum(:max_daily_evaluations) }
        rescue StandardError
          {}
        end

        # One grouped query rather than a result lookup per row.
        def last_run_times(policies)
          ids = policies.map(&:id)
          return {} if ids.empty?

          RAAF::Eval::Models::ContinuousEvaluationResult
            .where(evaluation_policy_id: ids)
            .group(:evaluation_policy_id)
            .maximum(:created_at)
        rescue StandardError
          {}
        end

        def set_policy
          @policy = EvaluationPolicy.find(params[:id])
        end

        def policy_params
          # Handle both param keys (namespaced model vs simple)
          policy_key = if params[:raaf_eval_models_evaluation_policy].present?
                         :raaf_eval_models_evaluation_policy
                       else
                         :evaluation_policy
                       end

          permitted = params.require(policy_key).permit(
            :name, :description, :agent_name, :environment, :model_pattern, :version_pattern,
            :sampling_mode, :sample_rate, :sample_every_n, :max_daily_evaluations,
            :priority, :queue_name, :max_concurrent_evaluations, :max_retries,
            :retention_days, :retention_count, :active,
            evaluators: [:type, :name, :sample_rate, :agent_name, { checks: [], config: {} }],
            evaluator_names: [],
            metadata: {}
          )

          # Convert check_configs to evaluators format if provided
          # check_configs is always under :evaluation_policy key (from the form)
          if params[:evaluation_policy]&.dig(:check_configs).present?
            check_configs = params[:evaluation_policy][:check_configs]
            evaluators_hash = {}
            agent_names = []

            check_configs.each do |_check_id, config|
              # Use string keys for ActionController::Parameters (doesn't provide indifferent access for unpermitted nested params)
              next unless config["enabled"] == "1"

              evaluator_name = config["evaluator_name"]
              check_name = config["check_name"]
              agent_name = config["agent_name"]
              sampling_mode = config["sampling_mode"] || "every_n"
              sample_rate = config["sample_rate"].to_i
              sample_every_n = config["sample_every_n"].to_i if config["sample_every_n"].present?
              trials = config["trials"].to_i if config["trials"].present?
              consistency_mode = config["consistency_mode"] if config["consistency_mode"].present?
              trigger_mode = config["trigger_mode"] || "automatic"
              specific_evaluator = config["specific_evaluator"]

              agent_names << agent_name if agent_name.present?

              # Group checks by evaluator
              evaluator_type = fetch_evaluator_details(evaluator_name)&.dig(:type) || "rule_based"
              evaluators_hash[evaluator_name] ||= {
                "name" => evaluator_name,
                "type" => evaluator_type,
                "agent_name" => agent_name,
                "checks" => [],
                "check_sampling_modes" => {},
                "check_sample_rates" => {},
                "check_sample_every_n" => {},
                "check_trials" => {},
                "check_consistency_modes" => {},
                "check_trigger_modes" => {},
                "check_specific_evaluators" => {},
                "config" => {}
              }

              evaluators_hash[evaluator_name]["checks"] << check_name
              evaluators_hash[evaluator_name]["check_sampling_modes"][check_name] = sampling_mode
              evaluators_hash[evaluator_name]["check_sample_rates"][check_name] = sample_rate
              evaluators_hash[evaluator_name]["check_trigger_modes"][check_name] = trigger_mode

              # Store sample_every_n for every_n mode
              if sampling_mode == "every_n" && sample_every_n.present? && sample_every_n > 0
                evaluators_hash[evaluator_name]["check_sample_every_n"][check_name] = sample_every_n
              end

              # Store specific evaluator type for the check (e.g., consistency, no_regression)
              if specific_evaluator.present?
                evaluators_hash[evaluator_name]["check_specific_evaluators"][check_name] = specific_evaluator
              end

              # Store trials for statistical/consistency evaluators
              # Check both the overall evaluator type AND the specific evaluator (consistency checks)
              is_statistical = evaluator_type == "statistical" || specific_evaluator == "consistency"
              if trials.present? && trials > 0 && is_statistical
                evaluators_hash[evaluator_name]["check_trials"][check_name] = trials
              end

              # Store consistency_mode for statistical/consistency evaluators
              if consistency_mode.present? && is_statistical
                evaluators_hash[evaluator_name]["check_consistency_modes"][check_name] = consistency_mode
              end
            end

            permitted[:evaluators] = evaluators_hash.values

            # Set agent_name from selected checks
            # A policy matches spans by one agent name. Checks from two agents
            # used to be joined into "A, B", which matches nothing — the policy
            # saved, looked configured, and silently evaluated forever nothing.
            # The form only offers one agent's checks; this is the guard for
            # anything that gets past it.
            @cross_agent_checks = agent_names.uniq
            permitted[:agent_name] = agent_names.first if agent_names.uniq.size == 1

            # Default sampling_mode to every_n
            permitted[:sampling_mode] ||= "every_n"

            # Set policy-level sample_every_n (required for validation when sampling_mode is every_n)
            # Use the minimum from check configs or default to 10
            # Use string keys for ActionController::Parameters
            all_sample_every_n_values = check_configs.values
                                                     .filter { |c| c["enabled"] == "1" }
                                                     .filter_map do |c|
              c["sample_every_n"].presence&.to_i
            end
                                                     .select { |n| n > 0 }
            permitted[:sample_every_n] = all_sample_every_n_values.min || 10
          end

          # Convert evaluator_names to evaluators format if provided (legacy support)
          if permitted[:evaluator_names].present?
            permitted[:evaluators] = permitted[:evaluator_names].map do |name|
              { "name" => name, "type" => infer_evaluator_type(name), "config" => {} }
            end
            permitted.delete(:evaluator_names)
          end

          permitted
        end

        def fetch_evaluator_details(name)
          return unless defined?(RAAF::Eval::Continuous::EvaluatorDiscovery)

          RAAF::Eval::Continuous::EvaluatorDiscovery.get_details(name)
        end

        def infer_evaluator_type(name)
          # Try to get details from discovery
          if defined?(RAAF::Eval::Continuous::EvaluatorDiscovery)
            details = RAAF::Eval::Continuous::EvaluatorDiscovery.get_details(name)
            return details[:type] if details
          end
          "rule_based" # Default type
        end

        def default_policy_attributes
          {
            sampling_mode: "every_n",
            sample_every_n: 10,
            priority: 50,
            retention_days: 90,
            evaluators: [],
            agent_name: nil # Will be auto-derived from selected evaluators
          }
        end

        # Each check's average, taken from the `scores` hash the results
        # carry. Weights and thresholds are not stored anywhere, so the
        # design's weight column and threshold marker have nothing to draw
        # from and are left out rather than invented.
        #
        # Keyed as a check is named, `field:evaluator`, because that is how a
        # result is now written: one row per check, its `scores` being
        # `{ "field:evaluator" => score }`. A row written before results were
        # recorded per check keys on the field alone and reports under that
        # key, so the page can tell a check's own score from a figure several
        # evaluators went into — see PolicyShow#combined_note.
        #
        # Plucked rather than loaded: a row carries the whole evaluation in
        # `details`, and this needs one JSON column of it.
        def check_scores(policy)
          totals = Hash.new { |h, k| h[k] = { sum: 0.0, count: 0 } }

          policy.continuous_evaluation_results.where.not(scores: nil).pluck(:scores).each do |scores|
            next unless scores.is_a?(Hash)

            scores.each do |key, value|
              next unless value.is_a?(Numeric)

              totals[key.to_s][:sum] += value.to_f
              totals[key.to_s][:count] += 1
            end
          end

          totals.transform_values { |t| { average: t[:sum] / t[:count], count: t[:count] } }
        rescue StandardError
          {}
        end

        # The trend answers the window the topbar is set to, so it has to
        # bucket four windows that are three orders of magnitude apart. A day
        # per bar says nothing over an hour, and a minute per bar is 43,200
        # bars over a month, so each range names its own bucket.
        TREND_BUCKETS = {
          "1h" => { size: 1.minute, unit: "minute", format: "%H:%M" },
          "24h" => { size: 1.hour, unit: "hour", format: "%H:%M" },
          "7d" => { size: 1.day, unit: "day", format: "%b %d" },
          "30d" => { size: 1.day, unit: "day", format: "%b %d" }
        }.freeze

        # How the window is said out loud, in the card title and its empty
        # state.
        TREND_WINDOWS = { "1h" => "1 hour", "24h" => "24 hours",
                          "7d" => "7 days", "30d" => "30 days" }.freeze

        # One point per bucket, oldest first, with the buckets nothing ran in
        # left scoreless so the trend draws them as gaps rather than zeroes.
        #
        # Bucketed in Ruby rather than by `date_trunc`, which has no spelling
        # for "the minute this row falls in, counted back from now" and would
        # need a dialect per database besides.
        def trend_series(policy, range)
          bucket = TREND_BUCKETS.fetch(range)
          size = bucket[:size]
          count = (RAAF::Rails::TimeRange::RANGES.fetch(range) / size).round
          last = bucket_start(Time.current, size)
          # Stepped by duration rather than by seconds, so the day the clocks
          # go back stays one day instead of drifting an hour through the rest.
          starts = (0...count).map { |index| last - ((count - 1 - index) * size) }

          totals = trend_totals(policy, starts)

          starts.each_with_index.map do |at, index|
            scored = totals[index]
            { at: at, label: at.strftime(bucket[:format]),
              score: scored && (scored[:sum] / scored[:count]) }
          end
        rescue StandardError
          []
        end

        # Sum and count per bucket index, from a single pass over the window.
        def trend_totals(policy, starts)
          totals = {}

          policy.continuous_evaluation_results
                .where(created_at: starts.first..)
                .where.not(score: nil)
                .pluck(:created_at, :score)
                .each do |created_at, score|
                  index = (starts.bsearch_index { |start| start > created_at } || starts.size) - 1
                  next if index.negative?

                  entry = (totals[index] ||= { sum: 0.0, count: 0 })
                  entry[:sum] += score.to_f
                  entry[:count] += 1
                end

          totals
        end

        # The newest bucket starts at the top of the one the clock is in, so
        # the last bar is a whole bucket's worth rather than however many
        # seconds have passed since it opened.
        def bucket_start(time, size)
          case size
          when 1.day then time.beginning_of_day
          when 1.hour then time.beginning_of_hour
          else time.beginning_of_minute
          end
        end

        # `policy_params` records which agents the chosen checks belong to. More
        # than one is not a policy this system can run, so it is refused with a
        # message rather than saved as a name that matches nothing.
        def reject_cross_agent_checks(policy)
          agents = Array(@cross_agent_checks)
          return if agents.size <= 1

          policy.errors.add(
            :agent_name,
            "must belong to one agent — these checks span #{agents.to_sentence}"
          )
        end

        def calculate_today_stats
          results = @policy.continuous_evaluation_results.where("created_at >= ?", Time.current.beginning_of_day)
          {
            total: results.count,
            good: results.where(status: "good").count,
            average: results.where(status: "average").count,
            bad: results.where(status: "bad").count,
            error: results.where(status: "error").count,
            avg_score: results.average(:score)
          }
        end

        def fetch_available_evaluators
          if defined?(RAAF::Eval::Continuous::EvaluatorDiscovery)
            RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details
          else
            []
          end
        end
      end
    end
  end
end
