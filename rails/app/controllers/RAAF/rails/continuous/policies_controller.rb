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
          @policies = @policies.where(active: params[:active] == 'true') if params[:active].present?
          @policies = @policies.where('agent_name ILIKE ?', "%#{params[:agent]}%") if params[:agent].present?
          @policies = @policies.page(params[:page]).per(50)

          respond_to do |format|
            format.html do
              policy_list = RAAF::Rails::Continuous::PolicyList.new(policies: @policies)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Continuous Evaluation Policies") do
                render policy_list
              end
              render layout
            end
            format.json { render json: @policies }
          end
        end

        # GET /raaf/rails/continuous/policies/:id
        def show
          @recent_results = @policy.continuous_evaluation_results.order(created_at: :desc).limit(10)
          @today_stats = calculate_today_stats

          respond_to do |format|
            format.html do
              policy_show = RAAF::Rails::Continuous::PolicyShow.new(
                policy: @policy,
                today_stats: @today_stats,
                recent_results: @recent_results
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: @policy.name) do
                render policy_show
              end
              render layout
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
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "New Evaluation Policy") do
                render policy_form
              end
              render layout
            end
          end
        end

        # POST /raaf/rails/continuous/policies
        def create
          @policy = EvaluationPolicy.new(policy_params)
          if @policy.save
            redirect_to continuous_policy_path(@policy), notice: 'Policy created successfully.'
          else
            @available_evaluators = fetch_available_evaluators
            policy_form = RAAF::Rails::Continuous::PolicyForm.new(
              policy: @policy,
              evaluators: @available_evaluators
            )
            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "New Evaluation Policy") do
              render policy_form
            end
            render layout, status: :unprocessable_entity
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
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Edit #{@policy.name}") do
                render policy_form
              end
              render layout
            end
          end
        end

        # PATCH /raaf/rails/continuous/policies/:id
        def update
          if @policy.update(policy_params)
            redirect_to continuous_policy_path(@policy), notice: 'Policy updated successfully.'
          else
            @available_evaluators = fetch_available_evaluators
            policy_form = RAAF::Rails::Continuous::PolicyForm.new(
              policy: @policy,
              evaluators: @available_evaluators
            )
            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Edit #{@policy.name}") do
              render policy_form
            end
            render layout, status: :unprocessable_entity
          end
        end

        # DELETE /raaf/rails/continuous/policies/:id
        def destroy
          @policy.destroy
          redirect_to continuous_policies_path, notice: 'Policy deleted.'
        end

        # POST /raaf/rails/continuous/policies/:id/activate
        def activate
          @policy.update!(active: true)
          redirect_to continuous_policies_path, notice: 'Policy activated.'
        end

        # POST /raaf/rails/continuous/policies/:id/deactivate
        def deactivate
          @policy.update!(active: false)
          redirect_to continuous_policies_path, notice: 'Policy deactivated.'
        end

        # POST /raaf/rails/continuous/policies/:id/duplicate
        def duplicate
          new_policy = @policy.dup
          new_policy.name = "#{@policy.name} (Copy)"
          new_policy.active = false
          new_policy.save!
          redirect_to edit_continuous_policy_path(new_policy), notice: 'Policy duplicated.'
        end

        private

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
            evaluators: [:type, :name, :sample_rate, :agent_name, checks: [], config: {}],
            evaluator_names: [],
            metadata: {}
          )

          # Convert check_configs to evaluators format if provided
          # check_configs is always under :evaluation_policy key (from the form)
          if params[:evaluation_policy]&.dig(:check_configs).present?
            check_configs = params[:evaluation_policy][:check_configs]
            evaluators_hash = {}
            agent_names = []

            check_configs.each do |check_id, config|
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
            if agent_names.uniq.size == 1
              permitted[:agent_name] = agent_names.first
            elsif agent_names.any?
              permitted[:agent_name] = agent_names.uniq.join(", ")
            end

            # Default sampling_mode to every_n
            permitted[:sampling_mode] ||= "every_n"

            # Set policy-level sample_every_n (required for validation when sampling_mode is every_n)
            # Use the minimum from check configs or default to 10
            # Use string keys for ActionController::Parameters
            all_sample_every_n_values = check_configs.values
                                                      .filter { |c| c["enabled"] == "1" }
                                                      .filter_map { |c| c["sample_every_n"].to_i if c["sample_every_n"].present? }
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
          if defined?(RAAF::Eval::Continuous::EvaluatorDiscovery)
            RAAF::Eval::Continuous::EvaluatorDiscovery.get_details(name)
          end
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
            sampling_mode: 'every_n',
            sample_every_n: 10,
            priority: 50,
            retention_days: 90,
            evaluators: [],
            agent_name: nil  # Will be auto-derived from selected evaluators
          }
        end

        def calculate_today_stats
          results = @policy.continuous_evaluation_results.where('created_at >= ?', Time.current.beginning_of_day)
          {
            total: results.count,
            good: results.where(status: 'good').count,
            average: results.where(status: 'average').count,
            bad: results.where(status: 'bad').count,
            error: results.where(status: 'error').count,
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
