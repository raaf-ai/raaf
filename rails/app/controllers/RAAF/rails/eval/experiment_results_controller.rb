# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for experiment results
      class ExperimentResultsController < BaseController
        before_action :set_experiment

        # GET /raaf/eval/experiments/:experiment_id/results
        def index
          scope = @experiment.experiment_results.includes(:dataset_item).recent
          scope = scope.where(status: params[:status]) if params[:status].present?

          @results = scope.page(params[:page]).per(50)
          @counts = @experiment.experiment_results.group(:status).count

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::ExperimentResultList.new(
                experiment: @experiment, results: @results, counts: @counts,
                filters: { status: params[:status] }
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(
                title: "#{@experiment.name} · results", crumb: "Evaluate", current: :experiments
              ) { render component }
              render layout
            end
            format.json { render json: @results }
          end
        end

        # GET /raaf/eval/experiments/:experiment_id/results/:id
        def show
          @result = @experiment.experiment_results.includes(:dataset_item).find(params[:id])

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::ExperimentResultShow.new(
                experiment: @experiment, result: @result,
                neighbours: neighbours(@result)
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(
                title: "Result ##{@result.dataset_item_id}", crumb: "Evaluate",
                current: :experiments
              ) { render component }
              render layout
            end
            format.json { render json: @result }
          end
        end

        private

        # The results either side of this one, so a run can be read straight
        # through rather than by going back to the table between every case.
        # In the order the run produced them, which is not the table's order —
        # that lists newest first. Stepping through a run backwards is the
        # stranger of the two, and the table is one click away either way.
        def neighbours(result)
          scope = @experiment.experiment_results
          { previous: scope.where("id < ?", result.id).order(id: :desc).first,
            next: scope.where("id > ?", result.id).order(:id).first }
        end

        def set_experiment
          @experiment = RAAF::Eval::Models::Experiment.find(params[:experiment_id])
        end
      end
    end
  end
end
