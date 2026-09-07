# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Controller for evaluator discovery and details
      class EvaluatorsController < BaseController
        # Policies whose matching spans are looked up on the show page. Each one
        # costs a scan of recent spans, and an evaluator used by more policies
        # than this is better approached from the policy list; the page says so
        # rather than dropping them quietly.
        POLICY_PANEL_LIMIT = 3

        # GET /raaf/rails/continuous/evaluators
        # Returns list of all available evaluators from the registry
        def index
          @evaluators = RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details

          respond_to do |format|
            format.html do
              render_in_layout(
                RAAF::Rails::Continuous::EvaluatorList.new(
                  evaluators: @evaluators,
                  policy_counts: policy_counts_for(@evaluators)
                ),
                title: "Evaluators", crumb: "Continuous"
              )
            end
            format.json { render json: @evaluators }
          end
        end

        # GET /raaf/rails/continuous/evaluators/:id
        # Returns details for a specific evaluator
        def show
          @evaluator = find_evaluator(params[:id])

          return render_missing_evaluator if @evaluator.nil?

          policies = RAAF::Eval::Models::EvaluationPolicy.using_evaluator(@evaluator[:name]).order(:name).to_a

          respond_to do |format|
            format.html do
              panelled = policies.first(POLICY_PANEL_LIMIT)

              render_in_layout(
                RAAF::Rails::Continuous::EvaluatorShow.new(
                  evaluator: @evaluator,
                  policies: policies,
                  spans_by_policy: matching_spans_for(panelled),
                  unpanelled: policies.size - panelled.size
                ),
                title: @evaluator[:name].to_s
              )
            end
            format.json { render json: @evaluator }
          end
        end

        private

        def find_evaluator(name)
          RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details.find do |e|
            e[:name] == name
          end
        end

        def matching_spans_for(policies)
          policies.index_with do |policy|
            RAAF::Rails::Continuous::PolicySpanLookup.recent_for(policy)
          end.transform_keys(&:id)
        end

        # How many policies grade with each evaluator, in one query per
        # evaluator name rather than one per row of a table nobody paginates.
        def policy_counts_for(evaluators)
          evaluators.each_with_object({}) do |evaluator, counts|
            name = evaluator[:name].to_s
            counts[name] = RAAF::Eval::Models::EvaluationPolicy.using_evaluator(name).count
          end
        end

        def render_in_layout(component, title:, crumb: "Continuous")
          layout = RAAF::Rails::Tracing::BaseLayout.new(title: title, crumb: crumb) do
            render component
          end
          render layout
        end

        # The HTML branch used to render a 'shared/not_found' template this
        # engine does not ship, so a mistyped evaluator name raised instead of
        # answering.
        def render_missing_evaluator
          respond_to do |format|
            format.html do
              render plain: "Evaluator not found: #{params[:id]}", status: :not_found
            end
            format.json { render json: { error: "Evaluator not found" }, status: :not_found }
          end
        end
      end
    end
  end
end
