# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Controller for managing evaluation policies
      class PoliciesController < BaseController
        before_action :set_policy, only: %i[show edit update destroy activate deactivate duplicate]

        # GET /raaf/rails/continuous/policies
        def index
          @policies = EvaluationPolicy.order(created_at: :desc)
          @policies = @policies.where(active: params[:active] == 'true') if params[:active].present?
          @policies = @policies.where('agent_name ILIKE ?', "%#{params[:agent]}%") if params[:agent].present?
          @policies = @policies.page(params[:page]).per(50)
        end

        # GET /raaf/rails/continuous/policies/:id
        def show
          @recent_results = @policy.evaluation_results.order(created_at: :desc).limit(10)
          @today_stats = @policy.today_stats
        end

        # GET /raaf/rails/continuous/policies/new
        def new
          @policy = EvaluationPolicy.new(default_policy_attributes)
          @available_evaluators = RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details
        end

        # POST /raaf/rails/continuous/policies
        def create
          @policy = EvaluationPolicy.new(policy_params)
          if @policy.save
            redirect_to continuous_policy_path(@policy), notice: 'Policy created successfully.'
          else
            @available_evaluators = RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details
            render :new, status: :unprocessable_entity
          end
        end

        # GET /raaf/rails/continuous/policies/:id/edit
        def edit
          @available_evaluators = RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details
        end

        # PATCH /raaf/rails/continuous/policies/:id
        def update
          if @policy.update(policy_params)
            redirect_to continuous_policy_path(@policy), notice: 'Policy updated successfully.'
          else
            @available_evaluators = RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details
            render :edit, status: :unprocessable_entity
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
          params.require(:evaluation_policy).permit(
            :name, :description, :agent_name, :environment, :model_pattern, :version_pattern,
            :sampling_mode, :sample_rate, :sample_every_n, :max_daily_evaluations,
            :priority, :queue_name, :max_concurrent_evaluations, :max_retries,
            :retention_days, :retention_count, :active,
            evaluators: [:type, :name, config: {}],
            metadata: {}
          )
        end

        def default_policy_attributes
          {
            sampling_mode: 'percentage',
            sample_rate: 10,
            priority: 50,
            retention_days: 90,
            evaluators: []
          }
        end
      end
    end
  end
end
