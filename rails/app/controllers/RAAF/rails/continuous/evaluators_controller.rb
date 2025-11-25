# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Controller for evaluator discovery and details
      class EvaluatorsController < BaseController
        # GET /raaf/rails/continuous/evaluators
        # Returns list of all available evaluators from the registry
        def index
          @evaluators = RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details

          respond_to do |format|
            format.html
            format.json { render json: @evaluators }
          end
        end

        # GET /raaf/rails/continuous/evaluators/:id
        # Returns details for a specific evaluator
        def show
          @evaluator = find_evaluator(params[:id])

          if @evaluator
            respond_to do |format|
              format.html
              format.json { render json: @evaluator }
            end
          else
            respond_to do |format|
              format.html { render 'shared/not_found', status: :not_found }
              format.json { render json: { error: 'Evaluator not found' }, status: :not_found }
            end
          end
        end

        private

        def find_evaluator(name)
          RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details.find do |e|
            e[:name] == name
          end
        end
      end
    end
  end
end
