# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for experiment results
      class ExperimentResultsController < BaseController
        before_action :set_experiment

        # GET /raaf/eval/experiments/:experiment_id/results
        def index
          @results = @experiment.experiment_results.includes(:dataset_item).recent
          respond_to do |format|
            format.json { render json: @results }
          end
        end

        # GET /raaf/eval/experiments/:experiment_id/results/:id
        def show
          @result = @experiment.experiment_results.find(params[:id])
          respond_to do |format|
            format.json { render json: @result }
          end
        end

        private

        def set_experiment
          @experiment = RAAF::Eval::Models::Experiment.find(params[:experiment_id])
        end
      end
    end
  end
end
